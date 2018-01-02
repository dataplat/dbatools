function Find-DbaLoginInGroup {
    <#
.SYNOPSIS
Finds Logins in Active Directory groups that have logins on the SQL Instance.

.DESCRIPTION
Outputs all the active directory groups members for a server, or limits it to find a specific AD user in the groups

.NOTES
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
Author: Simone Bizzotto, @niphlod

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a
collection and receive pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, current Windows login will be used.

.PARAMETER Login
Find all AD Groups used on the instance that an individual login is a member of.

.LINK
https://dbatools.io/Find-DbaLoginInGroup

.EXAMPLE
Find-DbaLoginInGroup -SqlInstance DEV01 -Login "MyDomain\Stephen.Bennett"

Returns all active directory groups with logins on Sql Instance DEV01 that contain the AD user Stephen.Bennett.

.EXAMPLE
Find-DbaLoginInGroup -SqlInstance DEV01

Returns all active directory users within all windows AD groups that have logins on the instance.

.EXAMPLE
Find-DbaLoginInGroup -SqlInstance DEV01 | Where-Object Login -like '*stephen*'

Returns all active directory users within all windows AD groups that have logins on the instance whose login contains 'stephen'

#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login
    )
    begin {
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        }
        catch {
            Write-warning "Failed to load Assembly needed"
            break
        }

        function Get-AllLogins {
            param
            (
                [string]$ADGroup,
                [string[]]$discard
            )
            begin {
                $output = @()
            }
            process {
                try {
                    $domain = $AdGroup.Split("\")[0]
                    $ads = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $domain)
                    [string]$groupName = $AdGroup
                    $group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ads, $groupName);
                    $subgroups = @()
                    foreach ($member in $group.Members) {
                        $memberDomain = $member.distinguishedname -Split "," | Where-Object { $_ -like "DC=*" } | Select-Object -first 1 | ForEach-Object { $_.ToUpper() -replace "DC=", '' }
                        if ($member.StructuralObjectClass -eq "group") {
                            $fullName = $memberDomain + "\" + $member.SamAccountName
                            if ($fullName -in $discard) {
                                Write-Verbose "skipping $fullName, already enumerated"
                                Continue
                            }
                            else {
                                $subgroups += $fullName
                            }
                        }
                        else {
                            $output += [PSCustomObject]@{
                                SqlInstance  = $server.Name
                                InstanceName = $server.ServiceName
                                ComputerName = $server.NetName
                                Login        = $memberDomain + "\" + $member.SamAccountName
                                DisplayName  = $member.DisplayName
                                MemberOf     = $AdGroup
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to connect to Group: $member."
                }
                $discard += $ADGroup
                foreach ($gr in $subgroups) {
                    if ($gr -notin $discard) {
                        $discard += $gr
                        Write-Verbose "Recursing Looking at $gr"
                        Get-AllLogins -ADGroup $gr -discard $discard
                    }
                }
            }
            end {
                $output
            }
        }
    }

    process {
        foreach ($Instance in $SqlInstance) {
            try {
                Write-Verbose "Connecting to $Instance"
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Warning "Failed to connect to: $Instance"
                continue
            }

            $AdGroups = $server.Logins | Where-Object { $_.LoginType -eq "WindowsGroup" -and $_.Name -ne "BUILTIN\Administrators" -and $_.Name -notlike "*NT SERVICE*" }

            foreach ($AdGroup in $AdGroups) {
                Write-Verbose "Looking at Group: $AdGroup"
                $ADGroupOut += Get-AllLogins $AdGroup.Name
            }

            if (-not $Login) {
                $res = $ADGroupOut
            }
            else {
                $res = $ADGroupOut | Where-Object { $Login -contains $_.Login }
                if ($res.Length -eq 0) {
                    Write-Warning "No logins matching $($Login -join ',') found connecting to $server"
                    continue
                }
            }
            Select-DefaultView -InputObject $res -Property SqlInstance, Login, MemberOf
        }
    }
}
