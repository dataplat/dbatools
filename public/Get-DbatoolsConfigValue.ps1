function Get-DbatoolsConfigValue {
    <#
    .SYNOPSIS
        Retrieves a specific dbatools configuration value by its exact name.

    .DESCRIPTION
        Retrieves the actual value stored in a specific dbatools configuration setting using its full name (Module.Name format). This function is primarily used internally by dbatools functions to access their configuration settings, but can also be used by DBAs in custom scripts to retrieve specific module preferences like connection timeouts, default file paths, or email settings. Unlike Get-DbatoolsConfig which lists multiple configurations, this function returns the raw value of a single setting with optional fallback support.

    .PARAMETER FullName
        Specifies the exact configuration setting name in Module.Name format (like 'sql.connection.timeout' or 'path.dbatoolsdata').
        Use this to retrieve specific dbatools module settings that control behavior like connection timeouts, default file paths, or email configurations.

    .PARAMETER Fallback
        Provides a default value to return when the specified configuration setting doesn't exist or is set to null.
        Use this in scripts when you need a reliable value even if the configuration hasn't been set, such as providing a default timeout of 30 seconds when no custom timeout is configured.

    .PARAMETER NotNull
        Forces the function to throw an error instead of returning null when no configuration value is found.
        Use this when your script requires a specific configuration setting to be present and should fail gracefully rather than continue with null values that could cause unexpected behavior.

    .OUTPUTS
        object

        Returns the value stored in the specified dbatools configuration setting. The return type depends on which configuration setting is retrieved - can be string, int, bool, datetime, or any object type stored in that configuration.

        Return behavior:
        - If the configuration exists and has a value, returns that value
        - If the configuration doesn't exist or is null AND -Fallback is specified, returns the Fallback value
        - If the configuration doesn't exist or is null AND -NotNull is specified, throws an error
        - If the configuration doesn't exist or is null AND neither -Fallback nor -NotNull is specified, returns $null

        Special handling: String values of "Mandatory" are automatically converted to $true and "Optional" are converted to $false to prevent switch parameter parsing issues.

    .NOTES
        Tags: Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsConfigValue

    .EXAMPLE
        PS C:\> Get-DbatoolsConfigValue -Name 'System.MailServer'

        Returns the configured value that was assigned to the key 'System.MailServer'

    .EXAMPLE
        PS C:\> Get-DbatoolsConfigValue -Name 'Default.CoffeeMilk' -Fallback 0

        Returns the configured value for 'Default.CoffeeMilk'. If no such value is configured, it returns '0' instead.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSPossibleIncorrectComparisonWithNull", "")]
    [CmdletBinding()]
    param (
        [Alias('Name')]
        [Parameter(Mandatory)]
        [string]$FullName,
        [object]$Fallback,
        [switch]$NotNull
    )

    $FullName = $FullName.ToLowerInvariant()

    $temp = $null
    $temp = [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations[$FullName].Value
    if ($null -eq $temp) {
        $temp = $Fallback
    } else {
        # Prevent some potential [switch] parse issues
        if ($temp.ToString() -eq "Mandatory") { $temp = $true }
        if ($temp.ToString() -eq "Optional") { $temp = $false }
    }

    if ($NotNull -and ($null -eq $temp)) {
        Stop-Function -Message "No Configuration Value available for $Name" -EnableException $true -Category InvalidData -Target $FullName
    } else {
        return $temp
    }
}