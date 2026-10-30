-- Run once in the Supabase SQL editor (after moderation.sql).
-- The person who creates a room is its host. The host can lock the room,
-- clear it in bulk and replace its map. Everyone else can still draw unless it is locked.

alter table public.rooms add column if not exists host_hash text;
alter table public.rooms add column if not exists locked boolean not null default false;

create or replace function public.is_host(r text) returns boolean
language plpgsql stable as $$
declare k text; h text;
begin
  select host_hash into h from public.rooms where code = r;
  if h is null then return false; end if;
  k := coalesce((nullif(current_setting('request.headers', true), '')::json) ->> 'x-host-key', '');
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
  if coalesce(lk, false) and not public.is_host(rc) then raise exception 'Room is locked'; end if;
  if tg_op = 'DELETE' then return old; end if; return new;
end $$;
drop trigger if exists marks_guard on public.marks;
create trigger marks_guard before insert or update or delete on public.marks
  for each row execute function public.guard_marks();

create or replace function public.guard_marks_bulk() returns trigger
language plpgsql as $$
declare n int; rc text;
begin
  if current_user not in ('anon', 'authenticated') then return null; end if;
  select count(*) into n from old_rows;
  if n > 50 then
    for rc in select distinct room from old_rows loop
      if exists (select 1 from public.rooms where code = rc and host_hash is not null) and not public.is_host(rc) then
        raise exception 'Only the host can clear the room';
      end if;
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists marks_guard_bulk on public.marks;
create trigger marks_guard_bulk after delete on public.marks
  referencing old table as old_rows for each statement execute function public.guard_marks_bulk();

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
  if old.host_hash is not null and not public.is_host(old.code) then
    if new.map_path is distinct from old.map_path then raise exception 'Only the host can change the map'; end if;
    if old.locked and (new.grid is distinct from old.grid or new.credit is distinct from old.credit) then raise exception 'Room is locked'; end if;
  end if;
  return new;
end $$;
drop trigger if exists rooms_guard on public.rooms;
create trigger rooms_guard before update or delete on public.rooms
  for each row execute function public.guard_rooms();
