-- Word filter, enforced in the database.
create or replace function public.is_bad(t text) returns boolean
language plpgsql immutable as $$
declare n text; w text; sq text;
begin
  if t is null or t = '' then return false; end if;
  n := translate(lower(t), '0134578@$!|', 'oieastbasii');
  w := regexp_replace(n, '[^a-z]+', ' ', 'g');
  sq := regexp_replace(n, '[^a-z]', '', 'g');
  return w ~ '\y(?:nigg(?:er|a|ah|uh|az|as)s?|fag(?:s|got|gots|git|it|ot)?|dykes?|trann(?:y|ies)|shemales?|chinks?|gooks?|spic(?:s|k|ks)?|kikes?|coons?|wetbacks?|beaners?|pakis?|towelheads?|japs?|darkies?|retard(?:s|ed)?)\y'
      or sq ~ 'n+i+g{2,}(?:e+r+|a+h+|a+(?!r))|f+a+g{2,}o+t+';
end $$;

create or replace function public.reject_bad_marks() returns trigger
language plpgsql as $$
declare txt text;
begin
  select string_agg(x #>> '{}', ' ') into txt
  from jsonb_path_query(new.data::jsonb, '$.**') x
  where jsonb_typeof(x) = 'string';
  if public.is_bad(txt) then raise exception 'Text not allowed'; end if;
  return new;
end $$;
drop trigger if exists marks_bad on public.marks;
create trigger marks_bad before insert or update on public.marks
for each row execute function public.reject_bad_marks();

create or replace function public.reject_bad_room() returns trigger
language plpgsql as $$
begin
  if public.is_bad(new.code) then raise exception 'Room code not allowed'; end if;
  return new;
end $$;
drop trigger if exists rooms_bad on public.rooms;
create trigger rooms_bad before insert or update on public.rooms
for each row execute function public.reject_bad_room();

-- Map uploads must go through the upload-map function, so remove direct access to the maps bucket.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (coalesce(with_check, '') ilike '%maps%' or coalesce(qual, '') ilike '%maps%')
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end $$;
