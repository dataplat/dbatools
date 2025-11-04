function Stop-DbaDbEncryption {
    <#
    .SYNOPSIS
        Disables Transparent Data Encryption (TDE) on all user databases across a SQL Server instance

    .DESCRIPTION
        Disables Transparent Data Encryption (TDE) on all user databases within a SQL Server instance by calling Disable-DbaDbEncryption for each encrypted database found. This function automatically excludes system databases (master, model, tempdb, msdb, resource) and only processes databases that currently have encryption enabled.

        This is commonly used during instance decommissioning, migration scenarios where TDE is not required in the target environment, or when standardizing security configurations across multiple databases. The function provides a convenient way to decrypt multiple databases at once rather than handling each database individually.

        Each database is fully decrypted and the Database Encryption Key (DEK) is dropped to complete the TDE removal process. Certificates and master keys remain untouched and available for other purposes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Parallel
        Enables parallel processing of databases using runspace pools with 1-10 concurrent threads.
        Use this when disabling encryption on multiple databases to improve performance.
        Without this switch, databases are processed sequentially.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaDbEncryption

    .EXAMPLE
        PS C:\> Stop-DbaDbEncryption -SqlInstance sql01

        Removes this does that

    .EXAMPLE
        PS C:\> Stop-DbaDbEncryption -SqlInstance sql01 -Confirm:$false

        Disables TDE on all user databases on sql01 without prompting for confirmation.

    .EXAMPLE
        PS C:\> Stop-DbaDbEncryption -SqlInstance sql01, sql02 -Parallel -Confirm:$false

        Disables TDE on all user databases across multiple instances using parallel processing for improved performance
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Parallel,
        [switch]$EnableException
    )
    process {
        $splatDatabase = @{
            SqlInstance   = $SqlInstance
            SqlCredential = $SqlCredential
        }
        $InputObject = Get-DbaDatabase @splatDatabase | Where-Object Name -NotIn "master", "model", "tempdb", "msdb", "resource"

        if (-not $Parallel) {
            # Sequential processing (original behavior)
            $stepCounter = 0
            foreach ($db in $InputObject) {
                $server = $db.Parent
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Disabling encryption for $($db.Name) on $($server.Name)" -TotalSteps $InputObject.Count
                try {
                    if ($db.EncryptionEnabled) {
                        $db | Disable-DbaDbEncryption -Confirm:$false
                    } else {
                        Write-Message -Level Verbose "Encryption was not enabled for $($db.Name) on $($server.Name)"
                        $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, "Name as DatabaseName", EncryptionEnabled
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        } else {
            # Parallel processing using runspaces
            $disableScript = {
                param (
                    $ServerName,
                    $DatabaseName,
                    $SqlCredential,
                    $EnableException
                )
                $server = $null
                try {
                    # Create new connection for this thread
                    $splatConnection = @{
                        SqlInstance     = $ServerName
                        SqlCredential   = $SqlCredential
                        EnableException = $true
                    }
                    $server = Connect-DbaInstance @splatConnection
                    $db = $server.Databases[$DatabaseName]

                    if (-not $db) {
                        throw "Database $DatabaseName not found on $ServerName"
                    }

                    if ($db.EncryptionEnabled) {
                        # Disable encryption
                        $db.EncryptionEnabled = $false
                        $db.Alter()

                        # Wait for decryption to complete
                        $timeout = 120
                        $elapsed = 0
                        do {
                            Start-Sleep -Seconds 1
                            $elapsed++
                            $db.Refresh()
                        } while ($db.EncryptionEnabled -and $elapsed -lt $timeout)

                        # Drop the Database Encryption Key
                        if ($db.HasDatabaseEncryptionKey) {
                            $db.DatabaseEncryptionKey.Drop()
                        }

                        $db.Refresh()
                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $db.EncryptionEnabled
                            Status            = "Success"
                            Error             = $null
                        }
                    } else {
                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $false
                            Status            = "NotEncrypted"
                            Error             = $null
                        }
                    }
                } catch {
                    [PSCustomObject]@{
                        ComputerName      = $null
                        InstanceName      = $null
                        SqlInstance       = $ServerName
                        DatabaseName      = $DatabaseName
                        EncryptionEnabled = $null
                        Status            = "Failed"
                        Error             = $_.Exception.Message
                    }
                } finally {
                    if ($server) {
                        Disconnect-DbaInstance -SqlInstance $server
                    }
                }
            }

            # Create runspace pool with dbatools module imported
            $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $dbatools = Get-Module -Name dbatools
            if ($dbatools) {
                $initialSessionState.ImportPSModule($dbatools.Path)
            }
            $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10, $initialSessionState, $Host)
            $runspacePool.Open()

            $threads = @()

            foreach ($db in $InputObject) {
                $splatRunspace = @{
                    ServerName      = $db.Parent.Name
                    DatabaseName    = $db.Name
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                Write-Message -Level Verbose "Queuing database $($db.Name) on $($db.Parent.Name) for decryption"

                $thread = [powershell]::Create()
                $thread.RunspacePool = $runspacePool
                $null = $thread.AddScript($disableScript)
                $null = $thread.AddParameters($splatRunspace)

                $handle = $thread.BeginInvoke()
                $threads += [PSCustomObject]@{
                    Handle      = $handle
                    Thread      = $thread
                    Database    = $db.Name
                    Instance    = $db.Parent.Name
                    IsRetrieved = $false
                    Started     = Get-Date
                }
            }

            # Retrieve results from runspaces
            while ($threads | Where-Object { $_.IsRetrieved -eq $false }) {
                $totalThreads = ($threads | Measure-Object).Count
                $totalRetrievedThreads = ($threads | Where-Object { $_.IsRetrieved -eq $true } | Measure-Object).Count
                Write-Progress -Id 1 -Activity "Disabling encryption" -Status "Progress" -CurrentOperation "Processing: $totalRetrievedThreads/$totalThreads" -PercentComplete ($totalRetrievedThreads / $totalThreads * 100)

                foreach ($thread in ($threads | Where-Object { $_.IsRetrieved -eq $false })) {
                    if ($thread.Handle.IsCompleted) {
                        $result = $thread.Thread.EndInvoke($thread.Handle)
                        $thread.IsRetrieved = $true

                        if ($result) {
                            if ($result.Status -eq "Failed") {
                                Stop-Function -Message "Failed to disable encryption for $($result.DatabaseName) on $($result.SqlInstance): $($result.Error)" -Continue
                            } else {
                                $result | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, EncryptionEnabled
                            }
                        }

                        $thread.Thread.Dispose()
                    }
                }
                Start-Sleep -Milliseconds 500
            }

            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }
}