function Export-DbatoolsConfig {
    <#
    .SYNOPSIS
        Exports dbatools module configuration settings to a JSON file for backup or migration.

    .DESCRIPTION
        Exports dbatools configuration settings to a JSON file, allowing you to backup your current settings or migrate them to other machines. This function captures customized settings like connection timeouts, default database paths, and other module preferences that have been changed from their default values. You can export all settings or filter by specific modules, and optionally exclude settings that haven't been modified from defaults.

    .PARAMETER FullName
        Specifies the complete configuration setting name to export, including the module prefix (e.g., 'dbatools.path.dbatoolsdata').
        Use this when you need to export a specific configuration setting and know its exact full name.

    .PARAMETER Module
        Filters configuration settings to export only those belonging to a specific dbatools module (e.g., 'sql', 'path', 'message').
        Use this when you want to export all settings related to a particular functional area of dbatools rather than individual settings.

    .PARAMETER Name
        Specifies a pattern to match configuration setting names within the selected module, supporting wildcards.
        Use this with the Module parameter to narrow down which settings to export when you don't need all settings from a module.

    .PARAMETER Config
        Accepts configuration objects directly from Get-DbatoolsConfig for export to JSON.
        Use this when you want to filter or manipulate configuration objects before export, typically in pipeline operations.

    .PARAMETER ModuleName
        Exports module-specific configuration settings to predefined system locations rather than a custom path.
        Only exports settings marked as 'ModuleExport' that have been modified from defaults, useful for creating standardized module configuration packages.

    .PARAMETER ModuleVersion
        Specifies the version number to include in the exported configuration filename when using ModuleName parameter.
        Defaults to 1 and helps track different versions of module configuration exports for change management.

    .PARAMETER Scope
        Determines where to save module configuration files when using ModuleName parameter - user profile, shared location, or system-wide.
        Only file-based scopes are supported (registry scopes are blocked). Defaults to FileUserShared for cross-user accessibility.

    .PARAMETER OutPath
        Specifies the complete file path where the JSON configuration export will be saved, including the filename.
        The parent directory must exist or the export will fail, and any existing file at this location will be overwritten.

    .PARAMETER SkipUnchanged
        Excludes configuration settings that still have their original default values from the export.
        Use this to create smaller backup files containing only your customized settings, making configuration migration more focused.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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
        [Dataplat.Dbatools.Configuration.Config[]]
        $Config,

        [Parameter(ParameterSetName = "ModuleName", Mandatory = $true)]
        [string]
        $ModuleName,

        [Parameter(ParameterSetName = "ModuleName")]
        [int]
        $ModuleVersion = 1,

        [Parameter(ParameterSetName = "ModuleName")]
        [Dataplat.Dbatools.Configuration.ConfigScope]
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