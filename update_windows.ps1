function InstallAndUpdateModules {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames,

        [Parameter(Mandatory = $false)]
        [bool]$DisableUpdate = $false
    )

    foreach ($ModuleName in $ModuleNames) {
        # Check if module is installed
        if (-not(Get-Module -ListAvailable -Name $ModuleName)) {
            # If not installed, install for the current user
            Write-Output "Installing module $ModuleName"
            Install-Module -Name $ModuleName -Scope CurrentUser -Force
        }

        # Update the module
        if (-not $DisableUpdate) {
            Write-Output "Updating module $ModuleName"
            Update-Module -Name $ModuleName -Force
        }

        # Import the module
        Import-Module $ModuleName
    }
}

Write-Output "Prepare powershell modules"
# Call the function with the module names
InstallAndUpdateModules -ModuleNames @('PSWindowsUpdate', 'PendingReboot')

# Loop until no tasks are running
while ($true) {
    # Check if any task is running
    $runningTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Running' }

    if ($runningTasks) {
        Write-Output "There are running tasks. Waiting 10 seconds before checking again."
        Write-Output $runningTasks
        Start-Sleep -Seconds 10
    } else {
        Write-Output "No tasks are running. Continuing with the script."
        break
    }
}

Write-Output "Check Windows Update"
# 获取可用的 Windows 更新
$updates = Get-WindowsUpdate

# 检查是否有可用的更新
if ($updates.Count -gt 0) {
    Write-Output "Update available."
    Write-Output $updates
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose
    Write-Output "Windows Update installed."
} else {
    Write-Output "No Update available."
}

# check reboot pending
if ((Test-PendingReboot).IsRebootPending) {
    Stop-Computer -Force -Verbose
}
