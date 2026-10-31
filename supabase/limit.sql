drop trigger if exists rooms_limit on public.rooms;
drop table if exists public.room_creations;

create table if not exists public.room_limit_salt (
  salt text not null default gen_random_uuid()::text
);
insert into public.room_limit_salt select where not exists (select 1 from public.room_limit_salt);
alter table public.room_limit_salt enable row level security;

create table public.room_creations (
  hash text not null,
  created timestamptz not null default now()
);
create index room_creations_hash_idx on public.room_creations (hash, created);
alter table public.room_creations enable row level security;

create or replace function public.limit_room_creation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  hdr json;
  caller text;
  h text;
  recent int;
begin
  if exists (select 1 from public.rooms where code = new.code) then
    return new;
  end if;
  begin
    hdr := current_setting('request.headers', true)::json;
  exception when others then
    hdr := null;
  end;
  caller := trim(split_part(coalesce(hdr ->> 'x-forwarded-for', hdr ->> 'cf-connecting-ip', ''), ',', 1));
  if caller = '' then
    return new;
  end if;
  h := encode(sha256(convert_to(caller || (select salt from public.room_limit_salt limit 1), 'utf8')), 'hex');
  delete from public.room_creations where created < now() - interval '1 day';
  select count(*) into recent from public.room_creations where hash = h;
  if recent >= 10 then
    raise exception 'You have created too many rooms today. Rejoin one of your earlier rooms, or try again tomorrow.';
  end if;
  insert into public.room_creations (hash) values (h);
  return new;
end $$;

create trigger rooms_limit before insert on public.rooms
  for each row execute function public.limit_room_creation();
