param(
    [string[]]$TaskNamesToCheck = @(),
    [string[]]$TaskPathsToCheck = @(),
    [string[]]$ProcessNamesToCheck = @()
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
                Write-Host "Running task: $($_.TaskName) Path: $($_.Path)"
                return $true
            }
        }
        return $false
    }

    return $runningTasks
}

function Check-ProcessExists {
    param (
        [string[]]$processNames
    )
    foreach ($name in $processNames) {
        $process = Get-Process | Where-Object { $_.Name -like $name -or $_.ProcessName -like $name } | Select-Object -First 1
        if ($null -ne $process) {
            Write-Host "Process $_ is running, matching $name"
            return $true
        } else {
            return $false
        }
    }
}

# Loop until no specified tasks are running
$maxLoop = 10
while ($true) {
    if ($maxLoop -eq 0) {
        Write-Host "Max loop reached. Exiting the script."
        exit 1
    }
    Write-Host "Checking if any specified tasks are running."
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
$maxLoop = 10
while ($true) {
    if ($maxLoop -eq 0) {
        Write-Host "Max loop reached. Exiting the script."
        exit 1
    }
    Write-Host "Checking if any specified processes are running."
    $maxLoop--
    # Check if any specified task is running
    $runningTasks = Check-ProcessExists -processNames $ProcessNamesToCheck

    if ($runningTasks) {
        Write-Host "There are specified running processes. Waiting 10 seconds before checking again."
        Write-Host $runningTasks
        Start-Sleep -Seconds 10
    } else {
        Write-Host "No specified processes are running. Continuing with the script."
        break
    }
}

# check reboot pending
Write-Host "Checking if a reboot is pending."
if ((Test-PendingReboot).IsRebootPending) {
    Write-Host "Reboot is pending. Rebooting the machine."
    Stop-Computer -Force -Verbose
} else {
    Write-Host "No reboot is pending."
}
