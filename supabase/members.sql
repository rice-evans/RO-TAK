create table if not exists public.room_limit_salt (
  salt text not null default gen_random_uuid()::text
);
insert into public.room_limit_salt select where not exists (select 1 from public.room_limit_salt);
alter table public.room_limit_salt enable row level security;

create table if not exists public.room_members (
  room text not null references public.rooms(code) on delete cascade,
  key_hash text not null,
  id uuid not null default gen_random_uuid() unique,
  name text not null default '',
  net_hash text,
  editor boolean not null default false,
  seen timestamptz not null default now(),
  primary key (room, key_hash)
);
alter table public.room_members enable row level security;
revoke all on public.room_members from anon, authenticated;

create table if not exists public.room_bans (
  id uuid primary key default gen_random_uuid(),
  room text not null references public.rooms(code) on delete cascade,
  key_hash text not null,
  net_hash text,
  name text not null default '',
  created timestamptz not null default now()
);
create index if not exists room_bans_room_idx on public.room_bans (room);
create index if not exists room_bans_key_idx on public.room_bans (key_hash);
create index if not exists room_bans_net_idx on public.room_bans (net_hash);
alter table public.room_bans enable row level security;
revoke all on public.room_bans from anon, authenticated;

create or replace function public.member_hash() returns text
language plpgsql stable as $$
declare k text;
begin
  begin
    k := coalesce((nullif(current_setting('request.headers', true), '')::json) ->> 'x-member-key', '');
  exception when others then
    k := '';
  end;
  if k !~ '^[a-f0-9]{32}$' then return ''; end if;
  return encode(sha256(convert_to(k, 'utf8')), 'hex');
end $$;

create or replace function public.net_hash() returns text
language plpgsql stable security definer set search_path = public as $$
declare hdr json; ip text;
begin
  begin
    hdr := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    hdr := null;
  end;
  ip := trim(split_part(coalesce(hdr ->> 'x-forwarded-for', hdr ->> 'cf-connecting-ip', ''), ',', 1));
  if ip = '' then return ''; end if;
  return encode(sha256(convert_to(ip || (select salt from public.room_limit_salt limit 1), 'utf8')), 'hex');
end $$;

create or replace function public.my_banned_rooms() returns text[]
language plpgsql stable security definer set search_path = public as $$
declare mh text := public.member_hash(); nh text := public.net_hash();
begin
  if mh = '' and nh = '' then return '{}'; end if;
  return coalesce(array(
    select distinct b.room from public.room_bans b
    where ((mh <> '' and b.key_hash = mh) or (nh <> '' and b.net_hash = nh))
      and not public.is_host(b.room)
  ), '{}');
end $$;

create or replace function public.is_banned(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select r = any (public.my_banned_rooms());
$$;

create or replace function public.is_editor(r text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare mh text := public.member_hash();
begin
  return mh <> '' and exists (select 1 from public.room_members m where m.room = r and m.key_hash = mh and m.editor);
end $$;

update public.rooms set editor_hash = null where editor_hash is not null;

create or replace function public.guard_marks() returns trigger
language plpgsql as $$
declare rc text; lk boolean;
begin
  if current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then return old; end if; return new;
  end if;
  if tg_op = 'DELETE' then rc := old.room; else rc := new.room; end if;
  if public.is_banned(rc) then raise exception 'You were removed from this room'; end if;
  select locked into lk from public.rooms where code = rc;
  if coalesce(lk, false) and not public.is_host(rc) and not public.is_editor(rc) then raise exception 'Room is locked'; end if;
  if tg_op = 'DELETE' then return old; end if; return new;
end $$;

drop policy if exists marks_not_banned on public.marks;
create policy marks_not_banned on public.marks as restrictive for all to anon, authenticated
  using (not (room = any ((select public.my_banned_rooms())::text[])))
  with check (not (room = any ((select public.my_banned_rooms())::text[])));

drop policy if exists rooms_not_banned on public.rooms;
create policy rooms_not_banned on public.rooms as restrictive for all to anon, authenticated
  using (not (code = any ((select public.my_banned_rooms())::text[])))
  with check (not (code = any ((select public.my_banned_rooms())::text[])));

create or replace function public.room_join(r text, n text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare mh text := public.member_hash(); nh text := public.net_hash(); nm text; mr public.room_members;
begin
  if mh = '' then raise exception 'Update RO-TAK to join rooms'; end if;
  if not exists (select 1 from public.rooms where code = r) then raise exception 'Room not found'; end if;
  if public.is_banned(r) then raise exception 'You were removed from this room'; end if;
  nm := left(trim(coalesce(n, '')), 16);
  if nm = '' or public.is_bad(nm) then nm := 'Player'; end if;
  if not exists (select 1 from public.room_members where room = r and key_hash = mh)
     and (select count(*) from public.room_members where room = r) >= 300 then
    delete from public.room_members where room = r and key_hash = (
      select key_hash from public.room_members where room = r and not editor order by seen limit 1);
  end if;
  insert into public.room_members as m (room, key_hash, name, net_hash)
  values (r, mh, nm, nullif(nh, ''))
  on conflict (room, key_hash) do update
    set name = excluded.name, net_hash = coalesce(excluded.net_hash, m.net_hash), seen = now()
  returning * into mr;
  return json_build_object('id', mr.id, 'editor', mr.editor);
end $$;

create or replace function public.room_people(r text) returns json
language plpgsql stable security definer set search_path = public as $$
declare mh text := public.member_hash();
begin
  if not public.is_host(r) then raise exception 'Only the host can do that'; end if;
  return json_build_object(
    'members', coalesce((
      select json_agg(json_build_object('id', id, 'name', name, 'editor', editor, 'me', key_hash = mh) order by seen desc)
      from public.room_members where room = r and seen > now() - interval '1 day'), '[]'::json),
    'bans', coalesce((
      select json_agg(json_build_object('id', id, 'name', name) order by created desc)
      from public.room_bans where room = r), '[]'::json));
end $$;

create or replace function public.room_set(r text, target uuid, act text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare m public.room_members;
begin
  if not public.is_host(r) then raise exception 'Only the host can do that'; end if;
  if act = 'unban' then
    delete from public.room_bans where room = r and id = target;
    return;
  end if;
  select * into m from public.room_members where room = r and id = target;
  if not found then raise exception 'Player not found'; end if;
  if m.key_hash = public.member_hash() then raise exception 'You cannot change yourself'; end if;
  if act = 'editor' then
    update public.room_members set editor = true where room = r and id = target;
  elsif act = 'viewer' then
    update public.room_members set editor = false where room = r and id = target;
  elsif act = 'kick' then
    insert into public.room_bans (room, key_hash, net_hash, name) values (r, m.key_hash, m.net_hash, m.name);
    delete from public.room_members where room = r and id = target;
  else
    raise exception 'Unknown action';
  end if;
end $$;

revoke execute on function public.member_hash() from public, anon, authenticated;
revoke execute on function public.net_hash() from public, anon, authenticated;
grant execute on function public.my_banned_rooms() to anon, authenticated;
grant execute on function public.is_banned(text) to anon, authenticated;
grant execute on function public.is_editor(text) to anon, authenticated;
grant execute on function public.room_join(text, text) to anon, authenticated;
grant execute on function public.room_people(text) to anon, authenticated;
grant execute on function public.room_set(text, uuid, text) to anon, authenticated;
