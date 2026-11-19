#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    // PS: the begin block VERBATIM, second half; see BeginScriptHead for the frame
    // and substitution inventory. The tail closes the relay guard, harvests the
    // 47-variable carry generically (Get-Variable by name - values only, the source
    // spellings resolve case-insensitively), reports the begin-latch flag, and
    // re-emits the continue marker when the loop-less -Continue escaped.
    private const string BeginScriptTail = """
        if (-not $CopyScheduleFrequencySubdayType) {
            $CopyScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Copy frequency subday type set to $CopyScheduleFrequencySubdayType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyScheduleFrequencySubdayInterval) {
            $CopyScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Copy frequency subday interval set to $CopyScheduleFrequencySubdayInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyScheduleFrequencyRelativeInterval) {
            $CopyScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Copy frequency relative interval set to $CopyScheduleFrequencyRelativeInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $CopyScheduleFrequencyRecurrenceFactor) {
            $CopyScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Copy frequency recurrence factor set to $CopyScheduleFrequencyRecurrenceFactor" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencyType) {
            $RestoreScheduleFrequencyType = "Daily"
            Write-Message -Message "Restore frequency type set to $RestoreScheduleFrequencyType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencyInterval) {
            $RestoreScheduleFrequencyInterval = "EveryDay"
            Write-Message -Message "Restore frequency interval set to $RestoreScheduleFrequencyInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencySubdayType) {
            $RestoreScheduleFrequencySubdayType = "Minutes"
            Write-Message -Message "Restore frequency subday type set to $RestoreScheduleFrequencySubdayType" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencySubdayInterval) {
            $RestoreScheduleFrequencySubdayInterval = 15
            Write-Message -Message "Restore frequency subday interval set to $RestoreScheduleFrequencySubdayInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencyRelativeInterval) {
            $RestoreScheduleFrequencyRelativeInterval = "Unused"
            Write-Message -Message "Restore frequency relative interval set to $RestoreScheduleFrequencyRelativeInterval" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }
        if (-not $RestoreScheduleFrequencyRecurrenceFactor) {
            $RestoreScheduleFrequencyRecurrenceFactor = 0
            Write-Message -Message "Restore frequency recurrence factor set to $RestoreScheduleFrequencyRecurrenceFactor" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        }

        # Checking for contradicting variables
        if ($NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -NoInitialization with -GenerateFullBackup or -UseExistingFullBackup" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        if ($UseBackupFolder -and ($GenerateFullBackup -or $NoInitialization -or $UseExistingFullBackup)) {
            Stop-Function -Message "Cannot use -UseBackupFolder with -GenerateFullBackup, -NoInitialization or -UseExistingFullBackup" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the subday interval
        if (($BackupScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -or $BackupScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Backup subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        } elseif (($BackupScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($BackupScheduleFrequencySubdayInterval -ge 1 -and $BackupScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Backup Subday interval $BackupScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the subday interval
        if (($CopyScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -or $CopyScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        } elseif (($CopyScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($CopyScheduleFrequencySubdayInterval -ge 1 -and $CopyScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Copy subday interval $CopyScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours'" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the subday interval
        if (($RestoreScheduleFrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -or $RestoreScheduleFrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        } elseif (($RestoreScheduleFrequencySubdayType -in 8, "Hours") -and (-not ($RestoreScheduleFrequencySubdayInterval -ge 1 -and $RestoreScheduleFrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Restore subday interval $RestoreScheduleFrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $DestinationSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the backup start date
        if (-not $BackupScheduleStartDate) {
            $BackupScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Backup start date set to $BackupScheduleStartDate" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } else {
            if ($BackupScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Backup start date $BackupScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }
        }

        # Check the back start time
        if (-not $BackupScheduleStartTime) {
            $BackupScheduleStartTime = '000000'
            Write-Message -Message "Backup start time set to $BackupScheduleStartTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup start time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the back end time
        if (-not $BackupScheduleEndTime) {
            $BackupScheduleEndTime = '235959'
            Write-Message -Message "Backup end time set to $BackupScheduleEndTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($BackupScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Backup end time $BackupScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the backup end date
        if (-not $BackupScheduleEndDate) {
            $BackupScheduleEndDate = '99991231'
        } elseif ($BackupScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Backup end date $BackupScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the copy start date
        if (-not $CopyScheduleStartDate) {
            $CopyScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Copy start date set to $CopyScheduleStartDate" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } else {
            if ($CopyScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Copy start date $CopyScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }
        }

        # Check the copy end date
        if (-not $CopyScheduleEndDate) {
            $CopyScheduleEndDate = '99991231'
        } elseif ($CopyScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Copy end date $CopyScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the copy start time
        if (-not $CopyScheduleStartTime) {
            $CopyScheduleStartTime = '000000'
            Write-Message -Message "Copy start time set to $CopyScheduleStartTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($CopyScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy start time $CopyScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the copy end time
        if (-not $CopyScheduleEndTime) {
            $CopyScheduleEndTime = '235959'
            Write-Message -Message "Copy end time set to $CopyScheduleEndTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($CopyScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Copy end time $CopyScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the restore start date
        if (-not $RestoreScheduleStartDate) {
            $RestoreScheduleStartDate = (Get-Date -format "yyyyMMdd")
            Write-Message -Message "Restore start date set to $RestoreScheduleStartDate" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } else {
            if ($RestoreScheduleStartDate -notmatch $RegexDate) {
                Stop-Function -Message "Restore start date $RestoreScheduleStartDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }
        }

        # Check the restore end date
        if (-not $RestoreScheduleEndDate) {
            $RestoreScheduleEndDate = '99991231'
        } elseif ($RestoreScheduleEndDate -notmatch $RegexDate) {
            Stop-Function -Message "Restore end date $RestoreScheduleEndDate needs to be a valid date with format yyyyMMdd" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the restore start time
        if (-not $RestoreScheduleStartTime) {
            $RestoreScheduleStartTime = '000000'
            Write-Message -Message "Restore start time set to $RestoreScheduleStartTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($RestoreScheduleStartTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore start time $RestoreScheduleStartTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }

        # Check the restore end time
        if (-not $RestoreScheduleEndTime) {
            $RestoreScheduleEndTime = '235959'
            Write-Message -Message "Restore end time set to $RestoreScheduleEndTime" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
        } elseif ($RestoreScheduleEndTime -notmatch $RegexTime) {
            Stop-Function -Message  "Restore end time $RestoreScheduleEndTime needs to match between '000000' and '235959'" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
            return
        }
        }
        $__continueEscaped = $false
    }
    $__carry = @{}
    foreach ($__carryName in @("azurebaseurl","backupcompression","backupretention","backupscheduleenddate","backupscheduleendtime","backupschedulefrequencyinterval","backupschedulefrequencyrecurrencefactor","backupschedulefrequencyrelativeinterval","backupschedulefrequencysubdayinterval","backupschedulefrequencysubdaytype","backupschedulefrequencytype","backupschedulestartdate","backupschedulestarttime","backupthreshold","copyscheduleenddate","copyscheduleendtime","copyschedulefrequencyinterval","copyschedulefrequencyrecurrencefactor","copyschedulefrequencyrelativeinterval","copyschedulefrequencysubdayinterval","copyschedulefrequencysubdaytype","copyschedulefrequencytype","copyschedulestartdate","copyschedulestarttime","databasecollection","databasestatus","historyretention","localpath","primarymonitorserversecuritymode","regexunc","restoredelay","restorescheduleenddate","restorescheduleendtime","restoreschedulefrequencyinterval","restoreschedulefrequencyrecurrencefactor","restoreschedulefrequencyrelativeinterval","restoreschedulefrequencysubdayinterval","restoreschedulefrequencysubdaytype","restoreschedulefrequencytype","restoreschedulestartdate","restoreschedulestarttime","restorethreshold","secondarymonitorserversecuritymode","sharedpath","sourceserver","sourceservername","useazure")) {
        $__carry[$__carryName] = Get-Variable -Name $__carryName -ValueOnly -ErrorAction Ignore
    }
    @{ __w4038State = @{ carry = $__carry; interrupted = [bool](Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -ErrorAction Ignore -ValueOnly) } }
    if ($__continueEscaped) { $__continueMarker }
} @__parameters -__boundSharedAzureExactlyOne:$__boundSharedAzureExactlyOne -__continueMarker:$__continueMarker -__boundVerbose:$__boundVerbose -__boundDebug:$__boundDebug @__commonParameters 3>&1 2>&1
""";

    private static string BeginScript => BeginScriptHead + "\n" + BeginScriptTail;
}
