function Write-DbatoolsConfigFile
{
<#
    .SYNOPSIS
        Handles config export to file.
    
    .DESCRIPTION
        Handles config export to file.
    
    .PARAMETER Config
        The configuration items to export.
    
    .PARAMETER Path
        The path to export to.
        Needs to point to the specific file to export to.
        Will create the folder structure if needed.
    
    .PARAMETER Replace
        Completely replaces previous file contents.
        By default, it will integrate settings into one coherent configuration file.
    
    .EXAMPLE
        PS C:\> Write-DbatoolsConfigFile -Config $items -Path .\file.json
    
        Exports all settings stored in $items to .\file.json.
        If the file already exists, the new settings will be merged into the existing file.
#>
    [CmdletBinding()]
    Param (
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $Config,
        
        [string]
        $Path,
        
        [switch]
        $Replace
    )
    
    begin
    {
        $parent = Split-Path -Path $Path
        if (-not (Test-Path $parent))
        {
            $null = New-Item $parent -ItemType Directory -Force
        }
        
        $data = @{ }
        if ((Test-Path $Path) -and (-not $Replace))
        {
            foreach ($item in (Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json))
            {
                $data[$item.FullName] = $item
            }
        }
    }
    process
    {
        foreach ($item in $Config)
        {
            $datum = @{
                Version  = 1
                FullName = $item.FullName
            }
            if ($item.SimpleExport)
            {
                $datum["Data"] = $item.Value
            }
            else
            {
                $persisted = [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ConvertToPersistedValue($item.Value)
                $datum["Value"] = $persisted.PersistedValue
                $datum["Type"] = $persisted.PersistedType
                $datum["Style"] = "default"
            }
            
            $data[$item.FullName] = [pscustomobject]$datum
        }
    }
    end
    {
        $data.Values | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
    }
}
