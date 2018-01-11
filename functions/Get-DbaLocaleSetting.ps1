function Get-DbaLocaleSetting {
    <#
      .SYNOPSIS
      Gets the Locale settings on a computer.

      .DESCRIPTION
      Gets the Locale settings on one or more computers.

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .PARAMETER EnableException
      By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
      This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
      Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: OS
      dbatools PowerShell module (https://dbatools.io)
      Copyright (C) 2016 Chrissy LeMaire
      License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

      .LINK
      https://dbatools.io/Get-DbaLocaleSetting

      .EXAMPLE
      Get-DbaLocaleSetting -ComputerName sqlserver2014a

      Gets the Locale settings on computer sqlserver2014a.

      .EXAMPLE
      'sql1','sql2','sql3' | Get-DbaLocaleSetting

      Gets the Locale settings on computers sql1, sql2 and sql3.

      .EXAMPLE
      Get-DbaLocaleSetting -ComputerName sql1,sql2 | Out-Gridview

      Gets the Locale settings on computers sql1 and sql2, and shows them in a grid view.

  #>
    [CmdletBinding()]
    Param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch][Alias('Silent')]$EnableException
    )

    BEGIN {
        $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
        $sessionoption = New-CimSessionOption -Protocol DCom
        $keyname = "Control Panel\International"
        $NS = 'root\cimv2'
        $Reg = 'StdRegProv'
        [UInt32]$CIMHiveCU = 2147483649
    }
    PROCESS {
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
                    $PropNames = Invoke-CimMethod -CimSession $CIMsession -Namespace $NS -ClassName $Reg -MethodName enumvalues -Arguments @{hDefKey = $CIMHiveCU; sSubKeyName = $keyname} |
                        Select-Object -ExpandProperty snames

                    foreach ($Name in $PropNames) {
                        $sValue = Invoke-CimMethod -CimSession $CIMsession -Namespace $NS -ClassName $Reg -MethodName GetSTRINGvalue -Arguments @{hDefKey = $CIMHiveCU; sSubKeyName = $keyname; sValueName = $Name} |
                            Select-Object -ExpandProperty svalue
                        $props.add($Name, $sValue)
                    }
                    [PSCustomObject]$props
                } #if CIMSession
                else {
                    Write-Message -Level Warning -Message "Can't create CIMSession on $computer"
                }
            } #if computername
            else {
                Write-Message -Level Warning -Message "Can't connect to $computer"
            }
        } #foreach computer
    } #PROCESS
} #function