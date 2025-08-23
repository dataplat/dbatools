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