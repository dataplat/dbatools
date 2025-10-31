function New-DbaCimSessionOptionWithTimeout {
    <#
    .SYNOPSIS
        Creates CIM session options with a configured operation timeout.

    .DESCRIPTION
        Internal helper function that creates CIM session options (WSManSessionOptions or DComSessionOptions)
        with the operation timeout configured from ComputerManagement.CimOperationTimeout setting.

        This ensures that CIM operations will timeout according to user configuration instead of
        using the system default timeout values.

    .PARAMETER Protocol
        The protocol to use for the CIM session options. Valid values are "Default" (WSMan), "Dcom".

    .NOTES
        Tags: ComputerManagement, CIM, Internal
        Author: dbatools team

        This is an internal function and should not be called directly by users.

    .EXAMPLE
        PS C:\> New-DbaCimSessionOptionWithTimeout -Protocol Default

        Creates WSManSessionOptions with the configured operation timeout.

    .EXAMPLE
        PS C:\> New-DbaCimSessionOptionWithTimeout -Protocol Dcom

        Creates DComSessionOptions with the configured operation timeout.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Default", "Dcom")]
        [string]$Protocol
    )

    $operationTimeout = Get-DbatoolsConfigValue -FullName "ComputerManagement.CimOperationTimeout" -Fallback (New-TimeSpan -Seconds 60)

    switch ($Protocol) {
        "Default" {
            $options = New-CimSessionOption -Protocol Default
            $options.Timeout = $operationTimeout
            return $options
        }
        "Dcom" {
            $options = New-CimSessionOption -Protocol Dcom
            $options.Timeout = $operationTimeout
            return $options
        }
    }
}
