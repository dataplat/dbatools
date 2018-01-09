#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Write-Message {
    <#
        .SYNOPSIS
            This function acts as central information node for dbatools.

        .DESCRIPTION
            This function acts as central information node for dbatools.
            Other functions hand off all their information output for processing to this function.

            This function will then handle:
            - Warning output
            - Error management for non-terminating errors (For errors that terminate execution or continue on with the next object use "Stop-Function")
            - Logging
            - Verbose output
            - Message output to users

            At what complexity what path for the information is chosen is determined by the configuration settings:
            message.maximuminfo
            message.maximumverbose
            message.maximumdebug
            message.minimuminfo
            message.minimumverbose
            message.minimumdebug
            Which can be set to any level from 1 through 9
            Depending on the configuration it is very possible to have multiple paths chosen simultaneously

        .PARAMETER Message
            The message to write/log. The function name and timestamp will automatically be prepended.

        .PARAMETER Level
            This parameter represents the verbosity of the message. The lower the number, the more important it is for a human user to read the message.
            By default, the levels are distributed like this:
            - 1-3 Direct verbose output to the user (using Write-Host)
            - 4-6 Output only visible when requesting extra verbosity (using Write-Verbose)
            - 1-9 Debugging information, written using Write-Debug
            The specific level of verbosity preference can be configured using the settings of the message.maximum and message.minimum namespace.

            In addition, it is possible to select the level "Warning" which moves the message out of the configurable range:
            The user will always be shown this message, unless he silences the entire thing with -EnableException

            Possible levels:
            Critical (1), Important / Output (2), Significant (3), VeryVerbose (4), Verbose (5), SomewhatVerbose (6), System (7), Debug (8), InternalComment (9), Warning (666)
            Either one of the strings or its respective number will do as input.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER FunctionName
            The name of the calling function.
            Will be automatically set, but can be overridden when necessary.

        .PARAMETER ErrorRecord
            If an error record should be noted with the message, add the full record here.
            Especially designed for use with Warning-mode, it can legally be used in either mode.
            The error will be added to the $Error variable and enqued in the dbatools debugging system.

        .PARAMETER Warning
            Deprecated, do not use anymore

        .PARAMETER Once
            Setting this parameter will cause this function to write the message only once per session.
            The string passed here and the calling function's name are used to create a unique ID, which is then used to register the action in the configuration system.
            Thus will the lockout only be written if called once and not burden the system unduly.
            This lockout will be written as a hidden value, to see it use Get-DbaConfig -Force.

        .PARAMETER OverrideExceptionMessage
            Disables automatic appending of exception messages.
            Use in cases where you already have a speaking message interpretation and do not need the original message.

        .PARAMETER Target
            If an ErrorRecord was passed, it is possible to add the object on which the error occurred, in order to simplify debugging / troubleshooting.

        .EXAMPLE
            PS C:\> Write-Message -Message 'Connecting to Database1' -Level 4 -EnableException $EnableException

            Writes the message 'Connecting to Database1'. By default, this will be
            - Written to the in-memory message log
            - Written to the logfile
            - Written to the Verbose stream (Write-Verbose)
            - Written to the Debug stream (Write-Debug)

        .EXAMPLE
            PS C:\> Write-Message -Message "Connecting to Database 2 failed" -EnableException $EnableException -Warning -ErrorRecord $_ -Target $Database

            Writes the message "Connecting to Database 2 failed". By default, this will be
            - Written to the in-memory message log
            - Written to the in-memory error queue
            - Written to the $error variable
            - Written to the logfile
            - Written to the error log files
            - Written to the Warning stream (Write-Warning, not if silent)
            - Written to the Debug stream (Write-Debug)

        .NOTES
            Author: Friedrich Weinmann
            Tags: debug

        .NOTES
            For Implementers transitioning from previously used cmdlets, rule of thumb:
            - Write-Host:    Level 2
            - Write-Verbose: Level 5
            - Write-Debug:   Level 8
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidDefaultValueForMandatoryParameter", "")]
    [CmdletBinding(DefaultParameterSetName = 'Level')]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Message,

        [Parameter(Mandatory = $true, ParameterSetName = 'Level')]
        [Sqlcollaborative.Dbatools.dbaSystem.MessageLevel]
        $Level = "Warning",

        [bool]
        [Alias('Silent')]
        $EnableException = $EnableException,

        [string]
        $FunctionName = ((Get-PSCallStack)[0].Command),

        [System.Management.Automation.ErrorRecord[]]
        $ErrorRecord,

        [Parameter(Mandatory = $true, ParameterSetName = 'Warning')]
        [switch]
        $Warning,

        [string]
        $Once,

        [switch]
        $OverrideExceptionMessage,

        [object]
        $Target
    )

    # Since it's internal, I set it to always silent. Will show up in tests, but not bother the end users with a reminder over something they didn't do.
    Test-DbaDeprecation -DeprecatedOn "1.0.0" -Parameter "Warning" -CustomMessage "The parameter -Warning has been deprecated and will be removed on release 1.0.0. Please use '-Level Warning' instead." -EnableException $true

    $timestamp = Get-Date
    $developerMode = [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::DeveloperMode

    $max_info = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumInformation
    $max_verbose = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumVerbose
    $max_debug = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumDebug
    $min_info = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumInformation
    $min_verbose = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumVerbose
    $min_debug = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumDebug
    $info_color = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::InfoColor
    $dev_color = [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::DeveloperColor

    #$coloredMessage = $Message
    $baseMessage = $Message
    foreach ($match in ($baseMessage | Select-String '<c=["''](.*?)["'']>(.*?)</c>' -AllMatches).Matches) {
        $baseMessage = $baseMessage -replace ([regex]::Escape($match.Value)), $match.Groups[2].Value
    }

    if ($developerMode) {
        $channels_future = @()
        if ((-not $EnableException) -and ($Level -eq [Sqlcollaborative.Dbatools.dbaSystem.MessageLevel]::Warning)) { $channels_future += "Warning" }
        if ((-not $EnableException) -and ($max_info -ge $Level) -and ($min_info -le $Level)) { $channels_future += "Information" }
        if (($max_verbose -ge $Level) -and ($min_verbose -le $Level)) { $channels_future += "Verbose" }
        if (($max_debug -ge $Level) -and ($min_debug -le $Level)) { $channels_future += "Debug" }

        if ((Test-Bound "Target") -and ($null -ne $Target)) {
            if ($Target.ToString() -ne $Target.GetType().FullName) { $targetString = " [T: $($Target.ToString())] " }
            else { $targetString = " [T: <$($Target.GetType().FullName.Split(".")[-1])>] " }
        }
        else { $targetString = "" }

        $newMessage = @"
[$FunctionName][$($timestamp.ToString("HH:mm:ss"))][L: $Level]$targetString[C: $channels_future][S: $EnableException][O: $($true -eq $Once)]
    $baseMessage
"@
    }
    else {
        $newMessage = "[$FunctionName][$($timestamp.ToString("HH:mm:ss"))] $baseMessage"
        $newColoredMessage = "[$FunctionName][$($timestamp.ToString("HH:mm:ss"))] $baseMessage"
    }
    if ($ErrorRecord -and ($Message -notmatch ([regex]::Escape("$($ErrorRecord[0].Exception.Message)"))) -and (-not $OverrideExceptionMessage)) {
        $baseMessage += " | $($ErrorRecord[0].Exception.Message)"
        $newMessage += " | $($ErrorRecord[0].Exception.Message)"
        $newColoredMessage += " | $($ErrorRecord[0].Exception.Message)"
    }

    #region Handle Input Objects
    if ($Target) {
        $targetType = $Target.GetType().FullName

        switch ($targetType) {
            "Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter" { $targetToAdd = $Target.InstanceName }
            "Microsoft.SqlServer.Management.Smo.Server" { $targetToAdd = ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$Target).InstanceName }
            default { $targetToAdd = $Target}
        }
        if ($targetToAdd.GetType().FullName -like "Microsoft.SqlServer.Management.Smo.*") { $targetToAdd = $targetToAdd.ToString() }
    }
    #endregion Handle Input Objects

    #region Handle Errors
    if ($ErrorRecord -and ((Get-PSCallStack)[1].Command -ne "Stop-Function")) {
        foreach ($record in $ErrorRecord) {
            $Exception = New-Object System.Exception($Message, $record.Exception)
            $newRecord = New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $record.CategoryInfo.Category, $targetToAdd)

            if ($EnableException) { Write-Error -Message $newRecord -Category $record.CategoryInfo.Category -TargetObject $targetToAdd -Exception $Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue }
            else { $null = Write-Error -Message $newRecord -Category $record.CategoryInfo.Category -TargetObject $targetToAdd -Exception $Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue 2>&1 }
        }
    }
    if ($ErrorRecord) {
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::WriteErrorEntry($ErrorRecord, $FunctionName, $timestamp, $baseMessage, $Host.InstanceId)
    }
    #endregion Handle Errors

    $channels = @()

    #region Warning Mode
    if ($Warning -or ($Level -like "Warning")) {
        if (-not $EnableException) {
            if ($PSBoundParameters.ContainsKey("Once")) {
                $OnceName = "MessageOnce.$FunctionName.$Once"

                if (-not (Get-DbaConfigValue -Name $OnceName)) {
                    Write-Warning $newMessage
                    Set-DbaConfig -Name $OnceName -Value $True -Hidden -EnableException -ErrorAction Ignore
                }
            }
            else {
                Write-Warning $newMessage
            }
            $channels += "Warning"
        }
        elseif ($developerMode) {
            Write-Host $newMessage -ForegroundColor $dev_color
        }

        Write-Debug $newMessage
        $channels += "Debug"
    }
    #endregion Warning Mode

    #region Message Mode
    else {
        if ((-not $EnableException) -and ($max_info -ge $Level) -and ($min_info -le $Level)) {
            if ($PSBoundParameters.ContainsKey("Once")) {
                $OnceName = "MessageOnce.$FunctionName.$Once"

                if (-not (Get-DbaConfigValue -Name $OnceName)) {
                    Write-HostColor -String $newColoredMessage -DefaultColor $info_color -ErrorAction Ignore
                    Set-DbaConfig -Name $OnceName -Value $True -Hidden -EnableException -ErrorAction Ignore
                }
            }
            else {
                Write-HostColor -String $newColoredMessage -DefaultColor $info_color -ErrorAction Ignore
            }
            $channels += "Information"
        }
        elseif ($developerMode) {
            Write-Host -Object $newMessage -ForegroundColor $dev_color
        }

        if (($max_verbose -ge $Level) -and ($min_verbose -le $Level)) {
            Write-Verbose $newMessage
            $channels += "Verbose"
        }

        if (($max_debug -ge $Level) -and ($min_debug -le $Level)) {
            Write-Debug $newMessage
            $channels += "Debug"
        }
    }
    #endregion Message Mode

    $channel_Result = $channels -join ", "
    if ($channel_Result) {
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::WriteLogEntry($Message, $channel_Result, $timestamp, $FunctionName, $Level, $Host.InstanceId, $targetToAdd)
    }
    else {
        [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::WriteLogEntry($Message, "None", $timestamp, $FunctionName, $Level, $Host.InstanceId, $targetToAdd)
    }
}