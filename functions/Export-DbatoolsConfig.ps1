function Export-DbatoolsConfig {
    <#
    .SYNOPSIS
        Exports configuration items to a Json file.

    .DESCRIPTION
        Exports configuration items to a Json file.

    .PARAMETER FullName
        Select the configuration objects to export by filtering by their full name.

    .PARAMETER Module
        Select the configuration objects to export by filtering by their module name.

    .PARAMETER Name
        Select the configuration objects to export by filtering by their name.

    .PARAMETER Config
        The configuration object(s) to export.
        Returned by Get-DbatoolsConfig.

    .PARAMETER ModuleName
        Exports all configuration pertinent to a module to a predefined path.
        Exported configuration items include all settings marked as 'ModuleExport' that have been changed from the default value.

    .PARAMETER ModuleVersion
        The configuration version of the module-settings to write.

    .PARAMETER Scope
        Which predefined path to write module specific settings to.
        Only file scopes are considered.
        By default it writes to the suer profile.

    .PARAMETER OutPath
        The path (filename included) to export to.
        Will fail if the folder does not exist, will overwrite the file if it exists.

    .PARAMETER SkipUnchanged
        If set, configuration objects whose value was not changed from its original value will not be exported.
        (Note: Settings that were updated with the same value as the original default will still be considered changed)

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .NOTES
        Tags: Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig | Export-DbatoolsConfig -OutPath '~/export.json'

        Exports all current settings to json.

    .EXAMPLE
        Export-DbatoolsConfig -Module message -OutPath '~/export.json' -SkipUnchanged

        Exports all settings of the module 'message' that are no longer the original default values to json.
    #>
    [CmdletBinding(DefaultParameterSetName = 'FullName')]
    Param (
        [Parameter(ParameterSetName = "FullName", Mandatory = $true)]
        [string]
        $FullName,

        [Parameter(ParameterSetName = "Module", Mandatory = $true)]
        [string]
        $Module,

        [Parameter(ParameterSetName = "Module", Position = 1)]
        [string]
        $Name = "*",

        [Parameter(ParameterSetName = "Config", Mandatory = $true, ValueFromPipeline = $true)]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $Config,

        [Parameter(ParameterSetName = "ModuleName", Mandatory = $true)]
        [string]
        $ModuleName,

        [Parameter(ParameterSetName = "ModuleName")]
        [int]
        $ModuleVersion = 1,

        [Parameter(ParameterSetName = "ModuleName")]
        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope = "FileUserShared",

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = 'Config')]
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = 'FullName')]
        [Parameter(Position = 2, Mandatory = $true, ParameterSetName = 'Module')]
        [string]
        $OutPath,

        [switch]
        $SkipUnchanged,

        [switch]$EnableException
    )

    begin {
        Write-Message -Level InternalComment -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")" -Tag 'debug', 'start', 'param'

        $items = @()

        if (($Scope -band 15) -and ($ModuleName)) {
            Stop-Function -Message "Cannot export modulecache to registry! Please pick a file scope for your export destination" -EnableException $EnableException -Category InvalidArgument -Tag 'fail', 'scope', 'registry'
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $ModuleName) {
            foreach ($item in $Config) { $items += $item }
            if ($FullName) { $items = Get-DbatoolsConfig -FullName $FullName }
            if ($Module) { $items = Get-DbatoolsConfig -Module $Module -Name $Name }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        if (-not $ModuleName) {
            try { Write-DbatoolsConfigFile -Config ($items | Where-Object { -not $SkipUnchanged -or -not $_.Unchanged } ) -Path $OutPath -Replace }
            catch {
                Stop-Function -Message "Failed to export to file" -EnableException $EnableException -ErrorRecord $_ -Tag 'fail', 'export'
                return
            }
        } else {
            if ($Scope -band 16) {
                Write-DbatoolsConfigFile -Config (Get-DbatoolsConfig -Module $ModuleName -Force | Where-Object ModuleExport | Where-Object Unchanged -NE $true) -Path (Join-Path $script:path_FileUserLocal "$($ModuleName.ToLowerInvariant())-$($ModuleVersion).json")
            }
            if ($Scope -band 32) {
                Write-DbatoolsConfigFile -Config (Get-DbatoolsConfig -Module $ModuleName -Force | Where-Object ModuleExport | Where-Object Unchanged -NE $true)  -Path (Join-Path $script:path_FileUserShared "$($ModuleName.ToLowerInvariant())-$($ModuleVersion).json")
            }
            if ($Scope -band 64) {
                Write-DbatoolsConfigFile -Config (Get-DbatoolsConfig -Module $ModuleName -Force | Where-Object ModuleExport | Where-Object Unchanged -NE $true)  -Path (Join-Path $script:path_FileSystem "$($ModuleName.ToLowerInvariant())-$($ModuleVersion).json")
            }
        }
    }
}