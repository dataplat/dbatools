function Test-DbaBackupInformation {
    <#
    .SYNOPSIS
        Tests a dbatools backup history object is correct for restoring

    .DESCRIPTION
        Input is normally from a backup history object generated from `Format-DbaBackupInformation`. This is then parse to check that it's valid for restore. Tests performed include:
          - Checking unbroken LSN chain
          - If the target database exists and WithReplace has been provided
          - If any files already exist, but owned by other databases
          - Creates any new folders required
          - That the backup files exists at the location specified, and can be seen by the Sql Instance
          - If no errors are found then the objects for that database will me marked as Verified

    .PARAMETER BackupHistory
        dbatools BackupHistory object. Normally this will have been process with `Select-` and then `Format-DbaBackupInformation`

    .PARAMETER SqlInstance
        The Sql Server instance that wil be performing the restore

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WithReplace
        By default we won't overwrite an existing database, this switch tells us you want to

    .PARAMETER Continue
        Switch to indicate a continuing restore

    .PARAMETER OutputScriptOnly
        Switch to disable path creation. Will write a warning that a path does not exist

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER VerifyOnly
        This switch indicates that you only wish to verify a restore, so runs a smaller number of tests as you won't be writing anything to the restore server

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .NOTES
        Tags: Backup, Restore, DisasterRecovery
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaBackupInformation

    .EXAMPLE
        PS C:\> $BackupHistory | Test-DbaBackupInformation -SqlInstance MyInstance
        PS C:\> $PassedDbs = $BackupHistory | Where-Object {$_.IsVerified -eq $True}
        PS C:\> $FailedDbs = $BackupHistory | Where-Object {$_.IsVerified -ne $True}

        Pass in a BackupHistory object to be tested against MyInstance.
        Those records that pass are marked as verified. We can then use the IsVerified property to divide the failures and successes

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$BackupHistory,
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$WithReplace,
        [switch]$Continue,
        [switch]$VerifyOnly,
        [switch]$OutputScriptOnly,
        [switch]$EnableException
    )

    begin {
        try {
            $RestoreInstance = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        $InternalHistory = @()
    }
    process {
        foreach ($bh in $BackupHistory) {
            $InternalHistory += $bh
        }
    }
    end {
        $RegisteredFileCheck = Get-DbaDbPhysicalFile -SqlInstance $RestoreInstance

        $Databases = $InternalHistory.Database | Select-Object -Unique
        foreach ($Database in $Databases) {
            $VerificationErrors = 0
            Write-Message -Message "Testing restore for $Database" -Level Verbose
            #Test we're only restoring backups from one database, or hilarity will ensure
            $DbHistory = $InternalHistory | Where-Object { $_.Database -eq $Database }
            if (( $DbHistory | Select-Object -Property OriginalDatabase -Unique ).Count -gt 1) {
                Write-Message -Message "Trying to restore $Database from multiple sources databases" -Level Warning
                $VerificationErrors++
            }
            #Test Db Existance on destination
            $DbCheck = Get-DbaDatabase -SqlInstance $RestoreInstance -Database $Database
            # Only do file and db tests if we're not verifing
            Write-Message -Level Verbose -Message "VerifyOnly = $VerifyOnly"
            If ($VerifyOnly -ne $true) {
                if ($null -ne $DbCheck -and ($WithReplace -ne $true -and $Continue -ne $true)) {
                    Write-Message  -Level Warning -Message "Database $Database exists, so WithReplace must be specified" -Target $database
                    $VerificationErrors++
                }

                $DBFileCheck = ($RegisteredFileCheck | Where-Object Name -eq $Database).PhysicalName
                $OtherFileCheck = ($RegisteredFileCheck | Where-Object Name -ne $Database).PhysicalName
                $DBHistoryPhysicalPaths = ($DbHistory | Select-Object -ExpandProperty filelist | Select-Object PhysicalName -Unique).PhysicalName
                $DBHistoryPhysicalPathsTest = Test-DbaPath -SqlInstance $RestoreInstance -Path $DBHistoryPhysicalPaths
                $DBHistoryPhysicalPathsExists = ($DBHistoryPhysicalPathsTest | Where-Object FileExists -eq $True).FilePath
                $pathSep = Get-DbaPathSep -Server $RestoreInstance
                foreach ($path in $DBHistoryPhysicalPaths) {
                    if (($DBHistoryPhysicalPathsTest | Where-Object FilePath -eq $path).FileExists) {
                        if ($path -in $DBFileCheck) {
                            #If the Files are owned by the db we're restoring check for Continue or WithReplace. If not, then report error otherwise just carry on
                            if ($WithReplace -ne $True -and $Continue -ne $True) {
                                Write-Message -Message "File $path already exists on $SqlInstance and WithReplace not specified, cannot restore" -Level Warning
                                $VerificationErrors++
                            }
                        } elseif ($path -in $OtherFileCheck) {
                            Write-Message -Message "File $path already exists on $SqlInstance and owned by another database, cannot restore" -Level Warning
                            $VerificationErrors++
                        } elseif ($path -in $DBHistoryPhysicalPathsExists -and $RestoreInstance.VersionMajor -gt 8) {
                            Write-Message -Message "File $path already exists on $($SqlInstance.ComputerName), not owned by any database in $SqlInstance, will not overwrite." -Level Warning
                            $VerificationErrors++
                        }
                    } else {
                        <#
                        dang, Split-Path converts path separators always using the "current system" settings
                        PS C:> Split-Path -Path '/var/opt/mssql/data/foo.bak' -Parent
                        \var\opt\mssql\data
                        I'm not aware of a safe way to change this so...we do a little hack.
                        #>
                        $pathSep = Get-DbaPathSep -Server $RestoreInstance
                        $ParentPath = Split-Path $path -Parent
                        $ParentPath = $ParentPath.Replace('\', $pathSep)
                        if (!(Test-DbaPath -SqlInstance $RestoreInstance -Path $ParentPath) ) {
                            if (-not $OutputScriptOnly) {
                                $ConfirmMessage = "`n Creating Folder $ParentPath on $SqlInstance `n"
                                if ($Pscmdlet.ShouldProcess("$Path on $SqlInstance `n `n", $ConfirmMessage)) {
                                    if (New-DbaDirectory -SqlInstance $RestoreInstance -Path $ParentPath) {
                                        Write-Message -Message "Created Folder $ParentPath on $SqlInstance" -Level Verbose
                                    } else {
                                        Write-Message -Message "Failed to create $ParentPath on $SqlInstance" -Level Warning
                                        $VerificationErrors++
                                    }
                                }
                            } else {
                                Write-Message -Message "Parth $ParentPath on $SqlInstance does not exist" -Level Verbose
                            }
                        }
                    }
                }
                #Test for LSN chain
                if ($true -ne $Continue) {
                    if (!($DbHistory | Test-DbaLsnChain)) {
                        Write-Message -Message "LSN Check failed" -Level Verbose
                        $VerificationErrors++
                    }
                }
            }

            #Test all backups readable
            $allpaths = $DbHistory | Select-Object -ExpandProperty FullName
            $allpaths_validity = Test-DbaPath -SqlInstance $RestoreInstance -Path $allpaths
            foreach ($path in $allpaths_validity) {
                if ($path.FileExists -eq $false -and ($path.FilePath -notlike 'http*')) {
                    Write-Message -Message "Backup File $($path.FilePath) cannot be read by $($RestoreInstance.Name). Does the service account ($($RestoreInstance.ServiceAccount)) have permission?" -Level Warning
                    $VerificationErrors++
                }
            }

            if ($VerificationErrors -eq 0) {
                Write-Message -Message "Marking $Database as verified" -Level Verbose
                $InternalHistory | Where-Object { $_.Database -eq $Database } | ForEach-Object { $_.IsVerified = $True }
            } else {
                Write-Message -Message "Verification errors  = $VerificationErrors - Has not Passed" -Level Verbose
            }
        }
        $InternalHistory
    }
}