function Get-DbaLocaleSetting {
    <#
    .SYNOPSIS
        Retrieves Windows locale settings from the registry on SQL Server computers for regional configuration analysis.

    .DESCRIPTION
        Retrieves Windows locale settings from the Control Panel\International registry key on one or more computers. These settings directly impact SQL Server's date/time formatting, currency display, number formatting, and collation behavior.

        Useful for auditing regional configurations across your SQL Server environment, troubleshooting locale-related issues, or ensuring consistent settings before SQL Server installations. The function accesses the current user's locale settings from HKEY_CURRENT_USER\Control Panel\International.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        Specifies the computer names where you want to retrieve Windows locale settings from the registry. Accepts SQL Server instance names but extracts only the computer portion.
        Use this to audit regional configurations across your SQL Server environment, especially before installations or when troubleshooting locale-related issues with date formats, currency display, or collation behavior.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Management, Locale, OS
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per computer with Windows locale settings from the HKEY_CURRENT_USER\Control Panel\International registry key.

        Standard properties (always included):
        - ComputerName: The name of the computer where locale settings were retrieved

        Additional properties (dynamically retrieved from registry):
        The command dynamically reads all values from the HKEY_CURRENT_USER\Control Panel\International registry key and adds them as properties. Common properties include:

        Locale and Language Settings:
        - Locale: The locale code (e.g., "00000410" for Italian)
        - LocaleName: The locale name in standard format (e.g., "it-IT")
        - sLanguage: The language abbreviation (e.g., "ITA")
        - sCurrency: The currency symbol (e.g., "€")

        Date and Time Formatting:
        - sLongDate: Format string for long date display
        - sShortDate: Format string for short date display
        - sTimeFormat: Format string for time display
        - sShortTime: Format string for short time display

        Numeric Formatting:
        - sDecimal: Decimal separator character (e.g., ".")
        - sList: List separator character (e.g., "," or ";")
        - iDigits: Number of digits after decimal separator

        Additional Integer Settings (prefixed with 'i'):
        - iCountry: Country/region identifier
        - iCurrDigits: Number of digits for currency
        - iCurrency: Currency format (0=prefix, 1=suffix)
        - iDate: Date format (0=M/D/Y, 1=D/M/Y, 2=Y/M/D)
        - iFirstDayOfWeek: First day of week (0=Sunday, 1=Monday, etc.)
        - iFirstWeekOfYear: First week of year definition
        - iLZero: Leading zero display (0=none, 1=display)
        - iTime: Time format (0=12-hour, 1=24-hour)
        - iTLZero: Time leading zero for hours (0=none, 1=display)

        Additional String Settings (prefixed with 's'):
        - sAM: AM symbol for 12-hour format
        - sPM: PM symbol for 12-hour format
        - sThousand: Thousands separator character

        Note: The actual properties returned depend on what is configured in the registry. Not all standard properties may be present on all systems. Use Select-Object * to see all properties available for a specific computer.

    .LINK
        https://dbatools.io/Get-DbaLocaleSetting

    .EXAMPLE
        PS C:\> Get-DbaLocaleSetting -ComputerName sqlserver2014a

        Gets the Locale settings on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaLocaleSetting

        Gets the Locale settings on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaLocaleSetting -ComputerName sql1,sql2 -Credential $credential

        Gets the Locale settings on computers sql1 and sql2 using SQL Authentication to authenticate to the servers.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch]$EnableException
    )
    begin {
        $ComputerName = $ComputerName | ForEach-Object { $_.split("\")[0] } | Select-Object -Unique
        $sessionoption = New-CimSessionOption -Protocol DCom
        $keyname = "Control Panel\International"
        $NS = 'root\cimv2'
        $Reg = 'StdRegProv'
        [UInt32]$CIMHiveCU = 2147483649
    }
    process {
        foreach ($computer in $ComputerName) {
            $props = @{ "ComputerName" = $computer }
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.FullComputerName ) {
                $Computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan"
                $CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
                if ( -not $CIMSession ) {
                    Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
                    $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                }
                if ( $CIMSession ) {
                    Write-Message -Level Verbose -Message "Getting properties from Registry Key"
                    $PropNames = Invoke-CimMethod -CimSession $CIMsession -Namespace $NS -ClassName $Reg -MethodName enumvalues -Arguments @{hDefKey = $CIMHiveCU; sSubKeyName = $keyname } | Select-Object -ExpandProperty snames

                    foreach ($Name in $PropNames) {
                        $sValue = Invoke-CimMethod -CimSession $CIMsession -Namespace $NS -ClassName $Reg -MethodName GetSTRINGvalue -Arguments @{hDefKey = $CIMHiveCU; sSubKeyName = $keyname; sValueName = $Name } | Select-Object -ExpandProperty svalue
                        $props.add($Name, $sValue)
                    }
                    [PSCustomObject]$props
                } else {
                    Write-Message -Level Warning -Message "Can't create CIMSession on $computer"
                }
            } else {
                Write-Message -Level Warning -Message "Can't connect to $computer"
            }
        }
    }
}