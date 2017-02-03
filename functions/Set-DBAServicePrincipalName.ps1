Function Set-DbaServicePrincipalName
{
<#
.SYNOPSIS
Sets an SPN for a given service account in active directory, and also enables delegation to the same SPN

.DESCRIPTION
This function will connect to Active Directory and search for an account. If the account is found, it will attempt to add an SPN. Once the SPN
is added, the function will also set delegation to that service. In order to run this function, the credential you provide must have write
access to Active Directory.

Note: This function supports -WhatIf

.PARAMETER spn
The SPN you want to add

.PARAMETER serviceaccount
The account you want the SPN added to

.PARAMETER Credential
The credential you want to use to connect to Active Directory to make the changes

.NOTES 
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Set-Set-DbaServicePrincipalName

.EXAMPLE
Set-DbaServicePrincipalName -spn MSSQLSvc\SQLSERVERA.domain.something -serviceaccount domain\account -Credential (Get-Credential)

Connects to active directory and adds a provided SPN to the given account.


#>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$spn,
        [Parameter(Mandatory = $true)]
        [string]$serviceaccount,
        [Parameter(Mandatory = $true)]
        [pscredential]$Credential
    )

    begin {
    }

    process {
        if ($serviceaccount -like "*\*") {
            Write-Verbose "Account provided in in domain\user format, stripping out domain info..."
            $serviceaccount = ($serviceaccount.split("\"))[1]
        }
        if ($serviceaccount -like "*@") {
            Write-Verbose "Account provided in in user@domain format, stripping out domain info..."
            $serviceaccount = ($serviceaccount.split("@"))[0]
        }

        $root = ([ADSI]"LDAP://RootDSE").defaultNamingContext
        $adsearch = New-Object System.DirectoryServices.DirectorySearcher
        $domain = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ("LDAP://" + $root) ,$($Credential.UserName),$($Credential.GetNetworkCredential().password)        
        $adsearch.SearchRoot = $domain
        $adsearch.Filter = $("(&(samAccountName={0}))" -f $serviceaccount)
        Write-Verbose "Looking for account $serviceAccount..."
        $Result = $adsearch.FindOne()

        #did we find the server account?

        If($Result -eq $null) {
            Write-Error "The account you specified for the SPN ($serviceAccount) doesn't exist"
        } else {
            #cool! add an spn

            $ADEntry = $Result.GetDirectoryEntry()
            if ($PSCmdlet.ShouldProcess("$spn","Adding SPN to service account")) {
                $ADEntry.Properties['serviceprincipalname'].Add($spn) | Out-Null
                Write-Verbose "Added SPN $spn to samaccount $serviceaccount"
                $ADEntry.CommitChanges()
            }

            #Don't forget delegation!
            $ADEntry = $Result.GetDirectoryEntry()
            if ($PSCmdlet.ShouldProcess("$spn","Adding delegation to service account for SPN")) {
                $ADEntry.Properties['msDS-AllowedToDelegateTo'].Add($spn) | Out-Null
                Write-Verbose "Added kerberos delegation to $spn for samaccount $serviceaccount"
                $ADEntry.CommitChanges()
            }
        }
    }

    end {
    }
}
