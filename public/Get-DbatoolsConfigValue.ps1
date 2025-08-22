function Get-DbatoolsConfigValue {
    <#
    .SYNOPSIS
        Retrieves a specific dbatools configuration value by its exact name.

    .DESCRIPTION
        Retrieves the actual value stored in a specific dbatools configuration setting using its full name (Module.Name format). This function is primarily used internally by dbatools functions to access their configuration settings, but can also be used by DBAs in custom scripts to retrieve specific module preferences like connection timeouts, default file paths, or email settings. Unlike Get-DbatoolsConfig which lists multiple configurations, this function returns the raw value of a single setting with optional fallback support.

    .PARAMETER FullName
        The full name (<Module>.<Name>) of the configured value to return.

    .PARAMETER Fallback
        A fallback value to use, if no value was registered to a specific configuration element.
        This basically is a default value that only applies on a "per call" basis, rather than a system-wide default.

    .PARAMETER NotNull
        By default, this function returns null if one tries to retrieve the value from either a Configuration that does not exist or a Configuration whose value was set to null.
        However, sometimes it may be important that some value was returned.
        By specifying this parameter, the function will throw an error if no value was found at all.

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