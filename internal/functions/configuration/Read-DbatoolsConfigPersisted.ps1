function Read-DbatoolsConfigPersisted
{
<#
    .SYNOPSIS
        Reads configurations from persisted file / registry.
    
    .DESCRIPTION
        Reads configurations from persisted file / registry.
    
    .PARAMETER Scope
        Where to read from.
    
    .PARAMETER Module
        Load module specific data.
        Use this to load on-demand configuration only when the module is imported.
        Useful when using the config system as cache.
    
    .PARAMETER ModuleVersion
        The configuration version of the module-settings to load.
    
    .PARAMETER Hashtable
        Rather than returning results, insert them into this hashtable.
    
    .PARAMETER Default
        When inserting into a hashtable, existing values are overwritten by default.
        Enabling this setting will cause it to only insert values if the key does not exist yet.
    
    .EXAMPLE
        Read-DbatoolsConfigPersisted -Scope 127
    
        Read all persisted default configuration items in the default mandated order.
#>
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    Param (
        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope,
        
        [string]
        $Module,
        
        [int]
        $ModuleVersion = 1,
        
        [System.Collections.Hashtable]
        $Hashtable,
        
        [switch]
        $Default
    )
    
    begin
    {
        #region Helper Functions
        function New-ConfigItem
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            param (
                $FullName,
                
                $Value,
                
                $Type,
                
                [switch]
                $KeepPersisted,
                
                [switch]
                $Enforced,
                
                [switch]
                $Policy
            )
            
            [pscustomobject]@{
                FullName      = $FullName
                Value         = $Value
                Type          = $Type
                KeepPersisted = $KeepPersisted
                Enforced      = $Enforced
                Policy        = $Policy
            }
        }
        
        function Read-Registry
        {
            [CmdletBinding()]
            param (
                $Path,
                
                [switch]
                $Enforced
            )
            
            if (-not (Test-Path $Path)) { return }
            
            $common = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
            
            foreach ($item in ((Get-ItemProperty -Path $Path -ErrorAction Ignore).PSObject.Properties | Where-Object Name -NotIn $common))
            {
                if ($item.Value -like "Object:*")
                {
                    $data = $item.Value.Split(":", 2)
                    New-ConfigItem -FullName $item.Name -Type $data[0] -Value $data[1] -KeepPersisted -Enforced:$Enforced -Policy
                }
                else
                {
                    try { New-ConfigItem -FullName $item.Name -Value ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ConvertFromPersistedValue($item.Value)) -Policy }
                    catch
                    {
                        Write-Message -Level Warning -Message "Failed to load configuration from Registry: $($item.Name)" -ErrorRecord $_ -Target "$Path : $($item.Name)"
                    }
                }
            }
        }
        #endregion Helper Functions
        
        if (-not $Hashtable) { $results = @{ } }
        else { $results = $Hashtable }
        
        if ($Module) { $filename = "$($Module.ToLowerInvariant())-$($ModuleVersion).json" }
        else { $filename = "psf_config.json" }
    }
    process
    {
        #region File - Computer Wide
        if ($Scope -band 64)
        {
            foreach ($item in (Read-DbatoolsConfigFile -Path (Join-Path $script:path_FileSystem $filename)))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion File - Computer Wide
        
        #region Registry - Computer Wide
        if (($Scope -band 4) -and (-not $script:NoRegistry))
        {
            foreach ($item in (Read-Registry -Path $script:path_RegistryMachineDefault))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion Registry - Computer Wide
        
        #region File - User Shared
        if ($Scope -band 32)
        {
            foreach ($item in (Read-DbatoolsConfigFile -Path (Join-Path $script:path_FileUserShared $filename)))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion File - User Shared
        
        #region Registry - User Shared
        if (($Scope -band 1) -and (-not $script:NoRegistry))
        {
            foreach ($item in (Read-Registry -Path $script:path_RegistryUserDefault))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion Registry - User Shared
        
        #region File - User Local
        if ($Scope -band 16)
        {
            foreach ($item in (Read-DbatoolsConfigFile -Path (Join-Path $script:path_FileUserLocal $filename)))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion File - User Local
        
        #region Registry - User Enforced
        if (($Scope -band 2) -and (-not $script:NoRegistry))
        {
            foreach ($item in (Read-Registry -Path $script:path_RegistryUserEnforced -Enforced))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion Registry - User Enforced
        
        #region Registry - System Enforced
        if (($Scope -band 8) -and (-not $script:NoRegistry))
        {
            foreach ($item in (Read-Registry -Path $script:path_RegistryMachineEnforced -Enforced))
            {
                if (-not $Default) { $results[$item.FullName] = $item }
                elseif (-not $results.ContainsKey($item.FullName)) { $results[$item.FullName] = $item }
            }
        }
        #endregion Registry - System Enforced
    }
    end
    {
        $results
    }
}
