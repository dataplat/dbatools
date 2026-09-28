function Get-AgentJobFingerprint {
    <#
    .SYNOPSIS
        Internal function. Builds a content fingerprint of a SQL Agent job so two jobs can be compared by definition rather than by date_modified.

    .DESCRIPTION
        Normalises the job properties, steps and schedules into a deterministic string and returns a SHA256 hash of it,
        plus the per-section text so callers can report which part differs.

        Deliberately excluded because they differ between instances even when the definition is identical:
        job_id, date_created, date_modified, version_number, schedule_id, schedule_uid, originating server,
        run history/status, and the job name (the caller already matched by name and may be using -NewName).

        Job-level IsEnabled is part of the fingerprint but kept in its own section so the caller can
        align it in place rather than recreating the job when nothing else differs.

    .PARAMETER Job
        The SMO job object.

    .PARAMETER OwnerLoginName
        Overrides the owner used in the fingerprint. Used when -Force is remapping a missing owner to sa on the destination.

    .PARAMETER IsEnabled
        Overrides the enabled state used in the fingerprint. Used when -DisableOnDestination means the desired
        destination state is disabled regardless of the source.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job]$Job,
        [string]$OwnerLoginName,
        [bool]$IsEnabled
    )

    $owner = if ($OwnerLoginName) { $OwnerLoginName } else { $Job.OwnerLoginName }
    $enabledValue = if ($PSBoundParameters.ContainsKey('IsEnabled')) { $IsEnabled } else { $Job.IsEnabled }
    $enabled = "IsEnabled=$enabledValue"

    $jobProps = @(
        "Owner=$owner"
        "Category=$($Job.Category)"
        "Description=$(($Job.Description -replace "`r`n", "`n").TrimEnd())"
        "StartStepID=$($Job.StartStepID)"
        "EmailLevel=$($Job.EmailLevel)"
        "OperatorToEmail=$($Job.OperatorToEmail)"
        "PageLevel=$($Job.PageLevel)"
        "OperatorToPage=$($Job.OperatorToPage)"
        "NetSendLevel=$($Job.NetSendLevel)"
        "OperatorToNetSend=$($Job.OperatorToNetSend)"
        "EventLogLevel=$($Job.EventLogLevel)"
        "DeleteLevel=$($Job.DeleteLevel)"
    ) -join "`n"

    $stepProps = foreach ($step in ($Job.JobSteps | Sort-Object ID)) {
        @(
            "ID=$($step.ID)"
            "Name=$($step.Name)"
            "SubSystem=$($step.SubSystem)"
            "Command=$(($step.Command -replace "`r`n", "`n").TrimEnd())"
            "DatabaseName=$($step.DatabaseName)"
            "DatabaseUserName=$($step.DatabaseUserName)"
            "Server=$($step.Server)"
            "ProxyName=$($step.ProxyName)"
            "OnSuccessAction=$($step.OnSuccessAction)"
            "OnSuccessStep=$($step.OnSuccessStep)"
            "OnFailAction=$($step.OnFailAction)"
            "OnFailStep=$($step.OnFailStep)"
            "RetryAttempts=$($step.RetryAttempts)"
            "RetryInterval=$($step.RetryInterval)"
            "OutputFileName=$($step.OutputFileName)"
            "JobStepFlags=$($step.JobStepFlags)"
            "CommandExecutionSuccessCode=$($step.CommandExecutionSuccessCode)"
            "OSRunPriority=$($step.OSRunPriority)"
        ) -join "`n"
    }
    $steps = $stepProps -join "`n--`n"

    $scheduleProps = foreach ($sched in ($Job.JobSchedules | Sort-Object Name)) {
        @(
            "Name=$($sched.Name)"
            "IsEnabled=$($sched.IsEnabled)"
            "FrequencyTypes=$($sched.FrequencyTypes)"
            "FrequencyInterval=$($sched.FrequencyInterval)"
            "FrequencySubDayTypes=$($sched.FrequencySubDayTypes)"
            "FrequencySubDayInterval=$($sched.FrequencySubDayInterval)"
            "FrequencyRelativeIntervals=$($sched.FrequencyRelativeIntervals)"
            "FrequencyRecurrenceFactor=$($sched.FrequencyRecurrenceFactor)"
            "ActiveStartDate=$($sched.ActiveStartDate.ToString('yyyyMMdd'))"
            "ActiveEndDate=$($sched.ActiveEndDate.ToString('yyyyMMdd'))"
            "ActiveStartTimeOfDay=$($sched.ActiveStartTimeOfDay)"
            "ActiveEndTimeOfDay=$($sched.ActiveEndTimeOfDay)"
        ) -join "`n"
    }
    $schedules = $scheduleProps -join "`n--`n"

    $normalised = "[job]`n$jobProps`n$enabled`n[steps]`n$steps`n[schedules]`n$schedules"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalised)) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $sha.Dispose()
    }

    [PSCustomObject]@{
        Hash      = $hash
        Job       = $jobProps
        Enabled   = $enabled
        Steps     = $steps
        Schedules = $schedules
    }
}