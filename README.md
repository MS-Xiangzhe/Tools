# Using

```sh
> powershell -f runbook_local.ps1 -Verbose  # Windows PowerShell 5
> pwsh -f runbook_local.ps1 -Verbose  # PowerShell 7, support multi-thread
```

# Runbook

Replace `$AzureConnection = (Connect-AzAccount -SubscriptionId 963c56be-5368-4fd1-9477-f7d214f9888a).context` to `$AzureConnection = (Connect-AzAccount -Identity).context`
