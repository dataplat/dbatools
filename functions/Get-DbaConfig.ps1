function Get-DbaConfig
{
	<#
		.SYNOPSIS
			Retrieves configuration elements by name.
		
		.DESCRIPTION
			Retrieves configuration elements by name.
			Can be used to search the existing configuration list.
		
		.PARAMETER Name
			Default: "*"
			The name of the configuration element(s) to retrieve.
			May be any string, supports wildcards.
		
		.PARAMETER Module
			Default: "*"
			Search configuration by module.
		
		.PARAMETER Force
			Overrides the default behavior and also displays hidden configuration values.
		
		.EXAMPLE
			PS C:\> Get-DbaConfig 'Mail.To'
			
			Retrieves the configuration element for the key "Mail.To"
	
		.EXAMPLE
			PS C:\> Get-DbaConfig -Force
	
			Retrieve all configuration elements from all modules, even hidden ones.
		
		.NOTES
			Author: Friedrich Weinmann
            Tags: Config
    #>
    [CmdletBinding()]
    Param (
        [string]
        $Name = "*",
        
        [string]
        $Module = "*",
        
        [switch]
        $Force
    )
    
    $Name = $Name.ToLower()
    $Module = $Module.ToLower()
    
    [sqlcollective.dbatools.Configuration.Config]::Cfg.Values | Where-Object { ($_.Name -like $Name) -and ($_.Module -like $Module) -and ((-not $_.Hidden) -or ($Force)) } | Sort-Object Module, Name
}