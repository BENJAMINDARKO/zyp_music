-- =============================================================
-- Deploy this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- This trigger auto-dispatches a GitHub repository_dispatch when
-- a suggestion is approved, completing the DB→CI/CD→CDN loop.
-- =============================================================

-- 1. Enable the async HTTP extension (safe to re-run)
create extension if not exists pg_net;

-- 2. Create or replace the webhook trigger function
create or replace function public.dispatch_genre_suggestion_to_github()
returns trigger as $$
declare
  github_pat text := 'YOUR_GITHUB_PERSONAL_ACCESS_TOKEN'; -- REPLACE with your ghp_ Classic Token!
  request_id bigint;
begin
  if (NEW.status = 'approved' and (OLD.status is null or OLD.status != 'approved')) then
    begin
      request_id := net.http_post(
        url := 'https://api.github.com/repos/BENJAMINDARKO/zyp_music/dispatches',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Accept', 'application/vnd.github+json',
          'Authorization', 'Bearer ' || github_pat,
          'X-GitHub-Api-Version', '2022-11-28',
          'User-Agent', 'Supabase-pg_net-Client'
        ),
        body := jsonb_build_object(
          'event_type', 'approve_suggestion',
          'client_payload', jsonb_build_object(
            'artist_name', NEW.artist_name,
            'suggested_genres', NEW.suggested_genres,
            'target_type', NEW.target_type,
            'status', NEW.status
          )
        )
      );
    exception when others then
      raise warning 'GitHub dispatch failed: %', SQLERRM;
    end;
  end if;
  return NEW;
end;
$$ language plpgsql security definer set search_path = public,net,extensions;

-- 3. Bind the trigger to the suggestions table
drop trigger if exists trigger_github_merge_trig on public.pending_metadata_suggestions;

create trigger trigger_github_merge_trig
  after update on public.pending_metadata_suggestions
  for each row
  execute function public.dispatch_genre_suggestion_to_github();

-- 4. Verify the trigger was created
select trigger_name, event_manipulation, action_statement
from information_schema.triggers
where event_object_table = 'pending_metadata_suggestions';
