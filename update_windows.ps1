param(
    [string[]]$TaskNamesToCheck = @(),
    [string[]]$TaskPathsToCheck = @()
)

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

Write-Output "Check Windows Update"
# 获取可用的 Windows 更新
$updates = Get-WindowsUpdate

# 检查是否有可用的更新
if ($updates.Count -gt 0) {
    Write-Output "Update available."
    Write-Output $updates
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose
    Write-Output "Windows Update installed."
} else {
    Write-Output "No Update available."
}

# Function to check specific running tasks
function Check-SpecificRunningTasks {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$TaskNames = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$TaskPaths = @()
    )

    $runningTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Running' }

    if ($TaskNames.Count -gt 0) {
        $runningTasks = $runningTasks | Where-Object { $TaskNames -contains $_.TaskName }
    }

    if ($TaskPaths.Count -gt 0) {
        $runningTasks = $runningTasks | Where-Object {
            foreach ($path in $TaskPaths) {
                if ($_.Path -like "*$path*") {
                    return $true
                }
            }
            return $false
        }
    }

    return $runningTasks
}

# Loop until no specified tasks are running
$maxLoop = 10
while ($true) {
    if ($maxLoop -eq 0) {
        Write-Output "Max loop reached. Exiting the script."
        exit 1
    }
    $maxLoop--
    # Check if any specified task is running
    $runningTasks = Check-SpecificRunningTasks -TaskNames $TaskNamesToCheck -TaskPaths $TaskPathsToCheck

    if ($runningTasks) {
        Write-Output "There are specified running tasks. Waiting 10 seconds before checking again."
        Write-Output $runningTasks
        Start-Sleep -Seconds 10
    } else {
        Write-Output "No specified tasks are running. Continuing with the script."
        break
    }
}

# check reboot pending
if ((Test-PendingReboot).IsRebootPending) {
    Stop-Computer -Force -Verbose
}
