function Set-DbaConfig
{
	<#
		.SYNOPSIS
			Sets configuration entries.
		
		.DESCRIPTION
			This function creates or changes configuration values.
			These are used in a larger framework to provide dynamic configuration information outside the PowerShell variable system.
		
		.PARAMETER Name
			Name of the configuration entry. If an entry of exactly this non-casesensitive name already exists, its value will be overwritten.
			Duplicate names across different modules are possible and will be treated separately.
			If a name contains namespace notation and no module is set, the first namespace element will be used as module instead of name. Example:
			-Name "Nordwind.Server"
			Is Equivalent to
			-Name "Server" -Module "Nordwind"
		
		.PARAMETER Value
			The value to assign to the named configuration element.
		
		.PARAMETER Module
			This allows grouping configuration elements into groups based on the module/component they server.
			If this parameter is not set, the configuration element is stored under its name only, which increases the likelyhood of name conflicts in large environments.
    
        .PARAMETER Description
            Using this, the configuration setting is given a description, making it easier for a user to comprehend, what a specific setting is for.
		
		.PARAMETER Hidden
			Setting this parameter hides the configuration from casual discovery. Configurations with this set will only be returned by Get-Config, if the parameter "-Force" is used.
			This should be set for all system settings a user should have no business changing (e.g. for Infrastructure related settings such as mail server).
		
		.PARAMETER Default
			Setting this parameter causes the system to treat this configuration as a default setting. If the configuration already exists, no changes will be performed.
			Useful in scenarios where for some reason it is not practical to automatically set defaults before loading userprofiles.
    
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
    
        .PARAMETER DisableHandler
            Internal Use Only.
            This parameter disables the configuration handlers.
            Configuration handlers are designed to automatically validate and process input set to a config value, in addition to writing the value.
            In many cases, this is used to improve performance, by forking the value location also to a static C#-field, which is then used, rather than searching a Hashtable.
            Sometimes it may only be used to introduce input validation.
            During module import, some handlers are registered and many values written to configuration.
            However, some of those values actually are already set as default values within the library. Processing a handler will cost a few ms.
            Add up a couple dozen such events and the delay is very notable. This parameter is designed to be used during module import only, in order to speed up the import.
		
		.EXAMPLE
			PS C:\> Set-DbaConfig -Name 'User' -Value "Friedrich" -Description "The user under which the show must go on."
	
			Creates a configuration entry named "User" with the value "Friedrich"
	
		.EXAMPLE
			PS C:\> Set-DbaConfig 'ConfigLink' 'https://www.example.com/config.xml' 'Company' -Hidden
	
			Creates a configuration entry named "ConfigLink" in the "Company" module with the value 'https://www.example.com/config.xml'.
			This entry is hidden from casual discovery using Get-Config.
	
		.EXAMPLE
			PS C:\> Set-DbaConfig 'Network.Firewall' '10.0.0.2' -Default
	
			Creates a configuration entry named "Firewall" in the "Network" module with the value '10.0.0.2'
			This is only set, if the setting does not exist yet. If it does, this command will apply no changes.
		
		.NOTES
			Author: Friedrich Weinmann
            Tags: Config
	#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $Name,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        $Value,
        
        [Parameter(Position = 2)]
        [string]
        $Module,
        
        [string]
        $Description,
        
        [switch]
        $Hidden,
        
        [switch]
        $Default,
        
        [switch]
        $Silent,
        
        [switch]
        $DisableHandler
    )
    
    #region Prepare Names
    $Name = $Name.ToLower()
    if ($Module) { $Module = $Module.ToLower() }
    
    if (-not $PSBoundParameters.ContainsKey("Module") -and ($Name -match ".+\..+"))
    {
        $r = $Name | select-string "^(.+?)\..+" -AllMatches
        $Module = $r.Matches[0].Groups[1].Value
        $Name = $Name.Substring($Module.Length + 1)
    }
    
    If ($Module) { $FullName = $Module, $Name -join "." }
    else { $FullName = $Name }
    #endregion Prepare Names
    
    #region Process Configuration Event Handlers
    if (-not $DisableHandler)
    {
        if ([sqlcollective.dbatools.Configuration.Config]::ConfigHandler[$FullName])
        {
            $TestResult = [sqlcollective.dbatools.Configuration.Config]::ConfigHandler[$FullName].Invoke($Value)
            if (-not $TestResult.Success)
            {
                Stop-Function -Message "Failed to process configuration: $($TestResult.Message)" -Silent $Silent -Category InvalidResult -Target $Value
                return
            }
        }
    }
    #endregion Process Configuration Event Handlers
    
    #region Process Record
    if (([sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName]) -and (-not $Default))
    {
        if ($PSBoundParameters.ContainsKey("Hidden")) { [sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName].Hidden = $Hidden }
        [sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName].Value = $Value
        if ($PSBoundParameters.ContainsKey("Description")) { [sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName].Description = $Description }
    }
    elseif (-not [sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName])
    {
        $Config = New-Object sqlcollective.dbatools.Configuration.Config
        $Config.Name = $name
        $Config.Module = $Module
        $Config.Description = $Description
        $Config.Value = $Value
        $Config.Hidden = $Hidden
        [sqlcollective.dbatools.Configuration.Config]::Cfg[$FullName] = $Config
    }
    #endregion Process Record
}