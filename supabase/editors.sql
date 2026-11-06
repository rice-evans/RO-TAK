alter table public.rooms add column if not exists editor_hash text;

create or replace function public.is_editor(r text) returns boolean
language plpgsql stable as $$
declare k text; h text;
begin
  select editor_hash into h from public.rooms where code = r;
  if h is null then return false; end if;
  k := coalesce((nullif(current_setting('request.headers', true), '')::json) ->> 'x-editor-key', '');
  return k <> '' and encode(sha256(convert_to(k, 'utf8')), 'hex') = h;
end $$;

create or replace function public.guard_marks() returns trigger
language plpgsql as $$
declare rc text; lk boolean;
begin
  if current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then return old; end if; return new;
  end if;
  if tg_op = 'DELETE' then rc := old.room; else rc := new.room; end if;
  select locked into lk from public.rooms where code = rc;
  if coalesce(lk, false) and not public.is_host(rc) and not public.is_editor(rc) then raise exception 'Room is locked'; end if;
  if tg_op = 'DELETE' then return old; end if; return new;
end $$;

create or replace function public.guard_rooms() returns trigger
language plpgsql as $$
begin
  if current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then return old; end if; return new;
  end if;
  if tg_op = 'DELETE' then
    if old.host_hash is not null and not public.is_host(old.code) then raise exception 'Only the host can delete the room'; end if;
    return old;
  end if;
  if new.host_hash is distinct from old.host_hash then raise exception 'Not allowed'; end if;
  if new.locked is distinct from old.locked and not public.is_host(old.code) then raise exception 'Only the host can lock the room'; end if;
  if new.editor_hash is distinct from old.editor_hash and not public.is_host(old.code) then raise exception 'Only the host can change editors'; end if;
  if old.host_hash is not null and not public.is_host(old.code) then
    if new.map_path is distinct from old.map_path then raise exception 'Only the host can change the map'; end if;
    if old.locked and not public.is_editor(old.code) and (new.grid is distinct from old.grid or new.credit is distinct from old.credit) then raise exception 'Room is locked'; end if;
  end if;
  return new;
end $$;
