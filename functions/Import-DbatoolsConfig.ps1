function Import-DbatoolsConfig {
    <#
    .SYNOPSIS
        Imports a json configuration file into the configuration system.

    .DESCRIPTION
        Imports a json configuration file into the configuration system.

    .PARAMETER Path
        The path to the json file to import.

    .PARAMETER ModuleName
        Import configuration items specific to a module from the default configuration paths.

    .PARAMETER ModuleVersion
        The configuration version of the module-settings to load.

    .PARAMETER Scope
        Where to import the module specific configuration items form.
        Only file-based scopes are supported for this.
        By default, all locations are queried, with user settings beating system settings.

    .PARAMETER IncludeFilter
        If specified, only elements with names that are similar (-like) to names in this list will be imported.

    .PARAMETER ExcludeFilter
        Elements that are similar (-like) to names in this list will not be imported.

    .PARAMETER Peek
        Rather than applying the setting, return the configuration items that would have been applied.

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
        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
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
                else { Set-DbatoolsConfig -FullName $value.FullName -Value ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ConvertFromPersistedValue($value.Value, $value.Type)) -EnableException:$EnableException }
            }
        }
    }
    end {

    }
}