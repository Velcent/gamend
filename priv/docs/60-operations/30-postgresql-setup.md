---
icon: hero-circle-stack
---

# PostgreSQL Setup

[Download PostgreSQL](https://www.postgresql.org)

## Database URL Configuration

Set the DATABASE_URL environment variable:

```bash
DATABASE_URL="postgresql://username:password@host:port/database"
# Example:
DATABASE_URL="postgresql://myuser:mypass@localhost:5432/game_server_prod"
```

The app will automatically detect PostgreSQL when DATABASE_URL is set or when POSTGRES_HOST and POSTGRES_USER environment variables are configured.

## Individual Environment Variables (Alternative)

You can also set individual database connection variables:

```bash
POSTGRES_HOST="your-postgres-host"
POSTGRES_PORT="5432"
POSTGRES_USER="your-username"
POSTGRES_PASSWORD="your-password"
POSTGRES_DB="your-database-name"
```

## Deployment Considerations

Popular PostgreSQL hosting options:

| Host | Notes |
|---|---|
| [Supabase](https://supabase.com) | Free tier available |
| [Neon](https://neon.tech) | Serverless PostgreSQL |
| [Fly.io Postgres](https://fly.io/docs/postgres/) | Managed PostgreSQL |
