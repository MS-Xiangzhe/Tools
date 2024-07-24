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
            Write-Host "Installing module $ModuleName"
            Install-Module -Name $ModuleName -Force
        }

        # Update the module
        if (-not $DisableUpdate) {
            Write-Host "Updating module $ModuleName"
            Update-Module -Name $ModuleName -Force
        }

        # Import the module
        Import-Module $ModuleName
    }
}

Write-Host "Prepare powershell modules"
# Call the function with the module names
InstallAndUpdateModules -ModuleNames @('PSWindowsUpdate', 'PendingReboot')

Write-Host "Check Windows Update"
# Get and install Windows updates
Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -Verbose

# Function to check specific running tasks
function Check-SpecificRunningTasks {
    param(
        [string[]]$TaskNames = @(),
        [string[]]$TaskPaths = @()
    )

    $runningTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Running' }

    $runningTasks = $runningTasks | Where-Object { $TaskNames -contains $_.TaskName }

    $runningTasks = $runningTasks | Where-Object {
        foreach ($path in $TaskPaths) {
            if ($_.Path -like "*$path*") {
                return $true
            }
        }
        return $false
    }

    return $runningTasks
}

# Loop until no specified tasks are running
$maxLoop = 10
while ($true) {
    if ($maxLoop -eq 0) {
        Write-Host "Max loop reached. Exiting the script."
        exit 1
    }
    $maxLoop--
    # Check if any specified task is running
    $runningTasks = Check-SpecificRunningTasks -TaskNames $TaskNamesToCheck -TaskPaths $TaskPathsToCheck

    if ($runningTasks) {
        Write-Host "There are specified running tasks. Waiting 10 seconds before checking again."
        Write-Host $runningTasks
        Start-Sleep -Seconds 10
    } else {
        Write-Host "No specified tasks are running. Continuing with the script."
        break
    }
}

# check reboot pending
if ((Test-PendingReboot).IsRebootPending) {
    Write-Host "Reboot is pending. Rebooting the machine."
    Stop-Computer -Force -Verbose
} else {
    Write-Host "No reboot is pending."
}
