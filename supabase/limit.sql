create table if not exists public.room_creations (
  ip text not null,
  created timestamptz not null default now()
);
create index if not exists room_creations_ip_idx on public.room_creations (ip, created);
alter table public.room_creations enable row level security;

create or replace function public.limit_room_creation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  hdr json;
  caller text;
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
  delete from public.room_creations where created < now() - interval '1 day';
  select count(*) into recent from public.room_creations where ip = caller;
  if recent >= 10 then
    raise exception 'You have created too many rooms today. Rejoin one of your earlier rooms, or try again tomorrow.';
  end if;
  insert into public.room_creations (ip) values (caller);
  return new;
end $$;

drop trigger if exists rooms_limit on public.rooms;
create trigger rooms_limit before insert on public.rooms
  for each row execute function public.limit_room_creation();
