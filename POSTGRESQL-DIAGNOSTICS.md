# PostgreSQL Diagnostics Runbook

The v1.1.0 toolbox includes a PostgreSQL-focused diagnostic stack for Kubernetes-hosted PostgreSQL, managed PostgreSQL, and traditional VM-based PostgreSQL targets.

## Installed PostgreSQL tooling

| Tool | Purpose |
|---|---|
| `psql` | Interactive SQL client |
| `pg_isready` | Readiness and connection checks |
| `pg_dump` / `pg_restore` | Backup and restore validation |
| `pgbench` | Basic synthetic performance testing |
| `pgbadger` | PostgreSQL log analysis and HTML reporting |
| `pgcli` | Enhanced interactive PostgreSQL shell |
| `pg_activity` | Real-time PostgreSQL activity monitoring |
| `psycopg` | Python PostgreSQL driver for custom scripts |
| `pg-diagnostics.sh` | Opinionated helper script included in the image |

## Connection model

Use standard libpq environment variables. Do not hard-code credentials in Helm values unless they are sourced from Kubernetes Secrets.

```bash
export PGHOST=postgres.postgres.svc.cluster.local
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=postgres
export PGPASSWORD='<secret>'
export PGSSLMODE=require   # use when TLS is enforced
```

Connection-string mode also works:

```bash
export DATABASE_URL='postgresql://user:pass@host:5432/db?sslmode=require'
```

The helper script intentionally does not print `PGPASSWORD` or `DATABASE_URL`.

## First-response checklist

```bash
pg_isready -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER"
psql -c 'select version();'
psql -c 'select now(), current_database(), current_user, inet_server_addr(), inet_server_port();'
pg-diagnostics.sh
```

If that fails, validate DNS and network before assuming the database is broken:

```bash
dig "$PGHOST"
nc -vz "$PGHOST" "${PGPORT:-5432}"
traceroute "$PGHOST" || true
openssl s_client -starttls postgres -connect "$PGHOST:${PGPORT:-5432}" -showcerts </dev/null
```

## Common triage queries

### Active sessions

```sql
select state, count(*)
from pg_stat_activity
group by state
order by count(*) desc;
```

### Long-running queries

```sql
select pid,
       usename,
       state,
       now() - query_start as age,
       wait_event_type,
       wait_event,
       left(query, 240) as query
from pg_stat_activity
where state <> 'idle'
order by age desc
limit 15;
```

### Blocking locks

```sql
select blocked_locks.pid as blocked_pid,
       blocked_activity.usename as blocked_user,
       blocking_locks.pid as blocking_pid,
       blocking_activity.usename as blocking_user,
       left(blocked_activity.query, 160) as blocked_statement,
       left(blocking_activity.query, 160) as blocking_statement
from pg_catalog.pg_locks blocked_locks
join pg_catalog.pg_stat_activity blocked_activity on blocked_activity.pid = blocked_locks.pid
join pg_catalog.pg_locks blocking_locks
  on blocking_locks.locktype = blocked_locks.locktype
 and blocking_locks.database is not distinct from blocked_locks.database
 and blocking_locks.relation is not distinct from blocked_locks.relation
 and blocking_locks.page is not distinct from blocked_locks.page
 and blocking_locks.tuple is not distinct from blocked_locks.tuple
 and blocking_locks.virtualxid is not distinct from blocked_locks.virtualxid
 and blocking_locks.transactionid is not distinct from blocked_locks.transactionid
 and blocking_locks.classid is not distinct from blocked_locks.classid
 and blocking_locks.objid is not distinct from blocked_locks.objid
 and blocking_locks.objsubid is not distinct from blocked_locks.objsubid
 and blocking_locks.pid != blocked_locks.pid
join pg_catalog.pg_stat_activity blocking_activity on blocking_activity.pid = blocking_locks.pid
where not blocked_locks.granted;
```

### Database sizes

```sql
select datname,
       pg_size_pretty(pg_database_size(datname)) as size
from pg_database
order by pg_database_size(datname) desc;
```

### Replication senders

```sql
select pid,
       usename,
       application_name,
       client_addr,
       state,
       sync_state,
       write_lag,
       flush_lag,
       replay_lag
from pg_stat_replication;
```

## Backup and restore validation

Schema-only export:

```bash
pg_dump --schema-only --file=/workspace/schema.sql
```

Compressed custom-format backup:

```bash
pg_dump --format=custom --file=/workspace/database.dump
pg_restore --list /workspace/database.dump | head -40
```

## Log analysis with pgBadger

Copy PostgreSQL logs into `/workspace`, then run:

```bash
pgbadger /workspace/postgresql.log -o /workspace/postgres-report.html
```

If the report is empty or low-value, verify PostgreSQL logging settings. At minimum, collect duration, connection, disconnection, lock waits, and temporary file activity in non-production before rolling aggressive logging into production.

## Kubernetes-specific patterns

Find likely PostgreSQL services:

```bash
kubectl get svc -A | grep -Ei 'postgres|pgsql|cnpg|zalando|crunchy'
kubectl get pods -A -o wide | grep -Ei 'postgres|pgsql|cnpg|zalando|crunchy'
```

Port-forward when direct service routing is blocked:

```bash
kubectl -n <namespace> port-forward svc/<postgres-service> 15432:5432
export PGHOST=127.0.0.1
export PGPORT=15432
pg_isready
pg-diagnostics.sh
```

## Operational cautions

`pgbench` can create load. Use it intentionally and avoid production unless you have approval and a rollback plan. `pg_dump` can also create meaningful read pressure on large databases. During an incident, diagnostics should reduce uncertainty, not become the second outage.
