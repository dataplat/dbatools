function Write-Message
{
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
            message.maximum.info
            message.maximum.verbose
            message.maximum.debug
            message.minimum.info
            message.minimum.verbose
            message.minimum.debug
            Which can be set to any level from 1 through 9
            Depending on the configuration it is very possible to have multiple paths chosen simultaneously
    
            NOTE: Logging not yet implemented!
        
        .PARAMETER Message
            The message to write/log. The function name and timestamp will automatically be prepended.
        
        .PARAMETER Level
            Any number from 1 through 9
            This parameter represents the verbosity of the message. The lower the number, the more important it is for a human user to read the message.
            By default, the levels are distributed like this:
            - 1-3 Direct verbose output to the user (using Write-Host or Write-Information)
            - 4-6 Output only visible when requesting extra verbosity (using Write-Verbose)
            - 1-9 Debugging information, written using Write-Debug
            The specific level of verbosity preference can be configured using the settings of the message.maximum and message.minimum namespace.
        
        .PARAMETER Silent
            Whether the silent switch was set in the calling function.
            If true, it will write errors, if any, but not write to the screen without explicit override using -Debug or -Verbose.
            If false, it will print a warning if in wrning mode. It will also be willing to write a message to the screen, if the level is within the range configured for that.
        
        .PARAMETER FunctionName
            The name of the calling function.
            Will be automatically set, but can be overridden when necessary.
        
        .PARAMETER ErrorRecord
            If an error record should be noted with the message, add the full record here.
            Especially designed for use with Warning-mode, it can legally be used in either mode.
            The error will be added to the $Error variable and enqued in the dbatools debugging system.
        
        .PARAMETER Warning
            This call is to be considered a warning. This will suppress the regular mode of checking which level of verbosity should occur.
            In warning mode, a warning is written unless the function is set to silent.
            In all cases, a Debug entry is written.
        
        .PARAMETER Target
            If an ErrorRecord was passed, it is possible to add the object on which the error eccoured, in order to simplify debugging / troubleshooting.
        
        .EXAMPLE
            PS C:\> Write-Message -Message 'Connecting to Database1' -Level 4 -Silent $Silent
    
            Writes the message 'Connecting to Database1'. By default, this will be
            - Written to the in-memory message log
            - Written to the logfile
            - Written to the Verbose stream (Write-Verbose)
            - Written to the Debug stream (Write-Debug)
    
        .EXAMPLE
            PS C:\> Write-Message -Message "Connecting to Database 2 failed: $($_.Exception.Message)" -Silent $silent -Warning -ErrorRecord $_ -Target $Database
    
            Writes the message "Connecting to Database 2 failed: $($_.Exception.Message)". By default, this will be
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
            For Implementers transitioning from previously used ccmdlets, rule of thumb:
            - Write-Host:    Level 2
            - Write-Verbose: Level 5
            - Write-Debug:   Level 8
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
    [CmdletBinding(DefaultParameterSetName = 'Level')]
    Param (
        [Parameter(Mandatory = $true)]
        [string]
        $Message,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Level')]
        [ValidateRange(1,9)]
        [int]
        $Level,
        
        [Parameter(Mandatory = $true)]
        [bool]
        $Silent,
        
        [string]
        $FunctionName = ((Get-PSCallStack)[0].Command),
        
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Warning')]
        [switch]
        $Warning,
        
        [object]
        $Target
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $NewMessage = "[$FunctionName][$timestamp] $Message"
    
    #region Handle Errors
    if ($ErrorRecord)
    {
        $Exception = New-Object System.Exception($Message, $ErrorRecord.Exception)
        $record = New-Object System.Management.Automation.ErrorRecord($Exception, "dbatools_$FunctionName", $ErrorRecord.CategoryInfo.Category, $Target)
        
        if ($Silent) { Write-Error -Message $record -Category $ErrorRecord.CategoryInfo.Category -TargetObject $Target -Exception $Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue }
        else { $null = Write-Error -Message $record -Category $ErrorRecord.CategoryInfo.Category -TargetObject $Target -Exception $Exception -ErrorId "dbatools_$FunctionName" -ErrorAction Continue 2>&1 }
    }
    #endregion Handle Errors
    
    #region Warning Mode
    if ($Warning)
    {
        if (-not $Silent) { Write-Warning $NewMessage }
        Write-Debug $NewMessage
    }
    #endregion Warning Mode
    
    #region Message Mode
    else
    {
        $max_info = Get-DbaConfigValue -Name 'message.maximum.info' -Fallback 3
        $max_verbose = Get-DbaConfigValue -Name 'message.maximum.verbose' -Fallback 6
        $max_debug = Get-DbaConfigValue -Name 'message.maximum.debug' -Fallback 9
        $min_info = Get-DbaConfigValue -Name 'message.minimum.info' -Fallback 1
        $min_verbose = Get-DbaConfigValue -Name 'message.minimum.verbose' -Fallback 4
        $min_debug = Get-DbaConfigValue -Name 'message.minimum.debug' -Fallback 1
        
        if ((-not $Silent) -and ($max_info -ge $Level) -and ($min_info -le $Level))
        {
            if ($Host.Version.Major -ge 5) { Write-Information $NewMessage }
            else { Write-Host $NewMessage -ForegroundColor (Get-DbaConfigValue -Name 'message.infocolor' -Fallback 'Cyan') }
        }
        
        if (($max_verbose -ge $Level) -and ($min_verbose -le $Level))
        {
            Write-Verbose $NewMessage
        }
        
        if (($max_debug -ge $Level) -and ($min_debug -le $Level))
        {
            Write-Debug $NewMessage
        }
    }
    #endregion Message Mode
}