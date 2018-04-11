function Get-DbaConfigValue {
    <#
        .SYNOPSIS
            Returns the configuration value stored under the specified name.

        .DESCRIPTION
            Returns the configuration value stored under the specified name.
            It requires the full name (<Module>.<Name>) and is usually only called by functions.

        .PARAMETER FullName
            The full name (<Module>.<Name>) of the configured value to return.

        .PARAMETER Fallback
            A fallback value to use, if no value was registered to a specific configuration element.
            This basically is a default value that only applies on a "per call" basis, rather than a system-wide default.

        .PARAMETER NotNull
            By default, this function returns null if one tries to retrieve the value from either a Configuration that does not exist or a Configuration whose value was set to null.
            However, sometimes it may be important that some value was returned.
            By specifying this parameter, the function will throw an error if no value was found at all.

        .EXAMPLE
            PS C:\> Get-DbaConfigValue -Name 'System.MailServer'

            Returns the configured value that was assigned to the key 'System.MailServer'

        .EXAMPLE
            PS C:\> Get-DbaConfigValue -Name 'Default.CoffeeMilk' -Fallback 0

            Returns the configured value for 'Default.CoffeeMilk'. If no such value is configured, it returns '0' instead.

        .NOTES
            Author: Friedrich Weinmann
            Tags: Config
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSPossibleIncorrectComparisonWithNull", "")]
    [CmdletBinding()]
    Param (
        [Alias('Name')]
        [Parameter(Mandatory = $true)]
        [string]
        $FullName,

        [object]
        $Fallback,

        [switch]
        $NotNull
    )

    $FullName = $FullName.ToLower()

    $temp = $null
    $temp = [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$FullName].Value
    if ($temp -eq $null) { $temp = $Fallback }

    if ($NotNull -and ($temp -eq $null)) {
        Stop-Function -Message "No Configuration Value available for $Name" -EnableException $true -Category InvalidData -Target $FullName
    }
    else {
        return $temp
    }
}
