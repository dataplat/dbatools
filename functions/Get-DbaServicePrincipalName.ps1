function Get-DbaServicePrincipalName
{
<#
.SYNOPSIS
Returns a list of set service principal names for a given computer/AD account

.DESCRIPTION
Get a list of set SPNs. SPNs are set at the AD account level. You can either retrieve set SPNs for a computer, or any SPNs set for
a given active directry account. You can query one, or both. You'll get a list of every SPN found for either search term.

.PARAMETER ServerName
The servers you want to return set SPNs for.

.PARAMETER AccountName
The accounts you want to retrieve set SPNs for.

.PARAMETER Credential
User credential to connect to the remote servers or active directory. This is a required parameter.

.NOTES 
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com
	
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	
.LINK
https://dbatools.io/Get-DbaServicePrincipalName

.EXAMPLE
Get-DbaServicePrincipalName -ServerName SQLSERVERA -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found

.EXAMPLE
Get-DbaServicePrincipalName -AccountName doamain\account -Credential (Get-Credential)

Returns a custom object with SearchTerm (domain account) and the SPNs that were found

.EXAMPLE
Get-DbaServicePrincipalName -ServerName SQLSERVERA,SQLSERVERB -Credential (Get-Credential)

Returns a custom object with SearchTerm (ServerName) and the SPNs that were found for multiple computers
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Servername,
        [Parameter(Mandatory = $false)]
        [string[]]$AccountName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )

    begin {


    }

    process {
        $spns = @()
        ForEach ($ac in $AccountName)
        {
            if ($ac -like "*\*") {
                Write-Verbose "Account name ($ac) provided in in domain\user format, stripping out domain info..."
                $ac = ($ac.split("\"))[1]
            }
            if ($ac -like "*@") {
                Write-Verbose "Account name ($ac) provided in in user@domain format, stripping out domain info..."
                $ac = ($ac.split("@"))[0]
            }

            $root = ([ADSI]"LDAP://RootDSE").defaultNamingContext
            $adsearch = New-Object System.DirectoryServices.DirectorySearcher
            $domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root) ,$($Credential.UserName),$($Credential.GetNetworkCredential().password)        
            $adsearch.SearchRoot = $domain
            $adsearch.Filter = $("(&(samAccountName={0}))" -f $ac)
            Write-Verbose "Looking for account $ac..."
            $Result = $adsearch.FindOne()

            ForEach ($s in $result.Properties.serviceprincipalname) {
                $spn = [pscustomobject] @{
                    SearchTerm = $ac
                    SPN = $s
                }
                $spns += $spn
            }

        }

        ForEach ($sv in $Servername)
        {
            $spnsForServer = Test-DbaServicePrincipalName -Servername $sv -Credential $Credential
            ForEach ($s in $spnsForServer | Where-Object {$_.IsSet -eq $true}) {
                $spn = [pscustomobject] @{
                    SearchTerm = $sv
                    SPN = $s.RequiredSPN
                }
                $spns += $spn
            }
        }
    }

    end {
        return $spns
    }
}