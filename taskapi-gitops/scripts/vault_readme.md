> ⚠️  IMPORTANT FOR THE WHOLE TEAM
>
> Vault dev mode stores ALL data in memory. This means:
>   - If the Vault pod restarts → all secrets, policies, and roles are wiped
>   - If your Codespace stops and restarts → run 'bash scripts/recover-vault.sh'
>   - If ExternalSecret shows SecretSyncedError after a restart → run recover-vault.sh
>
> This is expected behaviour in dev mode. Production Vault uses persistent
> storage (Raft or etcd) and is never wiped on restart.