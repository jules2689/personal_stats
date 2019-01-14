# personal_stats

Allows me to track some stats related to my work, and the distractions I experience there.

Installation
---
1. Create a slack token with the scopes listed below
2. Store the token in a `.env` file in the format `SLACK_TOKEN=XXX`
3. Run `bundle install`
4. Install `sqlite` with `brew install sqlite` (on mac)
5. Test it by running `ruby run.rb`
6. If successful, add `5 * * * * bash -lc "cd [PATH] && /opt/rubies/2.5.3/bin/ruby run.rb > /tmp/stats.log 2>&1"` to your crontab (replace `[PATH]` with the path to your repo)

Slack Token Scopes
---
- chat:write:bot
- chat:write:user
- groups:read
- im:read
- im:write
- mpim:read
- files:write:user
- search:read
