function Import-DbatoolsConfig {
    <#
    .SYNOPSIS
        Imports dbatools configuration settings from JSON files or default module paths.

    .DESCRIPTION
        Loads dbatools configuration settings from JSON files or retrieves module-specific settings from default configuration locations. This lets you restore saved dbatools preferences, share standardized settings across your team, or apply configuration baselines to multiple servers. You can import from local files, web URLs, or raw JSON strings, with optional filtering to selectively apply only the settings you need.

    .PARAMETER Path
        Specifies the path to JSON configuration files, web URLs, or raw JSON strings to import settings from.
        Use this to restore saved dbatools preferences, apply team-standard configurations, or load settings from remote locations.
        Accepts local file paths, HTTP/HTTPS URLs, or direct JSON content as strings.

    .PARAMETER ModuleName
        Specifies which dbatools module's configuration settings to import from default system locations.
        Use this to restore module-specific settings that were previously saved using Export-DbatoolsConfig.
        Common modules include 'message' for logging preferences and 'sql' for connection defaults.

    .PARAMETER ModuleVersion
        Specifies which version of the module configuration schema to load when importing persisted settings.
        Defaults to version 1, which works for most scenarios unless you're working with legacy configuration exports.
        Only change this if you're importing settings exported with a different version of dbatools.

    .PARAMETER Scope
        Controls which configuration storage locations to search when importing module settings.
        Options include FileUserLocal (user profile), FileUserShared (shared user settings), and FileSystem (system-wide).
        User settings override system settings when the same configuration exists in multiple locations.

    .PARAMETER IncludeFilter
        Specifies wildcard patterns to selectively import only matching configuration items from the source.
        Use this to import specific settings like 'sql.connection.*' for connection-related configs or 'logging.*' for logging preferences.
        Supports PowerShell -like wildcard matching with * and ? characters.

    .PARAMETER ExcludeFilter
        Specifies wildcard patterns to exclude specific configuration items during import.
        Use this to skip sensitive settings like credentials or environment-specific paths when sharing configurations.
        Applied after IncludeFilter, allowing you to include a category but exclude specific items within it.

    .PARAMETER Peek
        Returns the configuration items that would be imported without actually applying them to your session.
        Use this to preview configuration changes before applying them, especially when importing from unfamiliar sources.
        Helpful for validating configuration files and understanding what settings will be modified.

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
        https://dbatools.io/Import-DbatoolsConfig

    .EXAMPLE
        PS C:\> Import-DbatoolsConfig -Path '.\config.json'

        Imports the configuration stored in '.\config.json'

    .EXAMPLE
        PS C:\> Import-DbatoolsConfig -ModuleName message

        Imports all the module specific settings that have been persisted in any of the default file system paths.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingEmptyCatchBlock", "")]
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "Path")]
        [string[]]
        $Path,

        [Parameter(ParameterSetName = "ModuleName", Mandatory = $true)]
        [string]
        $ModuleName,

        [Parameter(ParameterSetName = "ModuleName")]
        [int]
        $ModuleVersion = 1,

        [Parameter(ParameterSetName = "ModuleName")]
        [Dataplat.Dbatools.Configuration.ConfigScope]
        $Scope = "FileUserLocal, FileUserShared, FileSystem",

        [Parameter(ParameterSetName = "Path")]
        [string[]]
        $IncludeFilter,

        [Parameter(ParameterSetName = "Path")]
        [string[]]
        $ExcludeFilter,

        [Parameter(ParameterSetName = "Path")]
        [switch]
        $Peek,

        [switch]$EnableException
    )

    begin {
        Write-Message -Level InternalComment -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")" -Tag 'debug', 'start', 'param'
    }
    process {
        #region Explicit Path
        foreach ($item in $Path) {
            try {
                if ($item -like "http*") { $data = Read-DbatoolsConfigFile -Weblink $item -ErrorAction Stop }
                else {
                    $pathItem = $null
                    try { $pathItem = Resolve-DbaPath -Path $item -SingleItem -Provider FileSystem }
                    catch { }
                    if ($pathItem) { $data = Read-DbatoolsConfigFile -Path $pathItem -ErrorAction Stop }
                    else { $data = Read-DbatoolsConfigFile -RawJson $item -ErrorAction Stop }
                }
            } catch { Stop-Function -Message "Failed to import $item" -EnableException $EnableException -Tag 'fail', 'import' -ErrorRecord $_ -Continue -Target $item }

            :element foreach ($element in $data) {
                #region Exclude Filter
                foreach ($exclusion in $ExcludeFilter) {
                    if ($element.FullName -like $exclusion) {
                        continue element
                    }
                }
                #endregion Exclude Filter

                #region Include Filter
                if ($IncludeFilter) {
                    $isIncluded = $false
                    foreach ($inclusion in $IncludeFilter) {
                        if ($element.FullName -like $inclusion) {
                            $isIncluded = $true
                            break
                        }
                    }

                    if (-not $isIncluded) { continue }
                }
                #endregion Include Filter

                if ($Peek) { $element }
                else {
                    try {
                        if (-not $element.KeepPersisted) { Set-DbatoolsConfig -FullName $element.FullName -Value $element.Value -EnableException }
                        else { Set-DbatoolsConfig -FullName $element.FullName -PersistedValue $element.Value -PersistedType $element.Type }
                    } catch {
                        Stop-Function -Message "Failed to set '$($element.FullName)'" -ErrorRecord $_ -EnableException $EnableException -Tag 'fail', 'import' -Continue -Target $item
                    }
                }
            }
        }
        #endregion Explicit Path

        if ($ModuleName) {
            $data = Read-DbatoolsConfigPersisted -Module $ModuleName -Scope $Scope -ModuleVersion $ModuleVersion

            foreach ($value in $data.Values) {
                if (-not $value.KeepPersisted) { Set-DbatoolsConfig -FullName $value.FullName -Value $value.Value -EnableException:$EnableException }
                else { Set-DbatoolsConfig -FullName $value.FullName -Value ([Dataplat.Dbatools.Configuration.ConfigurationHost]::ConvertFromPersistedValue($value.Value, $value.Type)) -EnableException:$EnableException }
            }
        }
    }
    end {

    }
}