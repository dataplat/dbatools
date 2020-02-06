function Find-DbaLoginInGroup {
    <#
    .SYNOPSIS
        Finds Logins in Active Directory groups that have logins on the SQL Instance.

    .DESCRIPTION
        Outputs all the active directory groups members for a server, or limits it to find a specific AD user in the groups

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        PSCredential object to connect under. If not specified, current Windows login will be used.

    .PARAMETER Login
        Find all AD Groups used on the instance that an individual login is a member of.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Group, Security
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/ | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaLoginInGroup

    .EXAMPLE
        PS C:\> Find-DbaLoginInGroup -SqlInstance DEV01 -Login "MyDomain\Stephen.Bennett"

        Returns all active directory groups with logins on Sql Instance DEV01 that contain the AD user Stephen.Bennett.

    .EXAMPLE
        PS C:\> Find-DbaLoginInGroup -SqlInstance DEV01

        Returns all active directory users within all windows AD groups that have logins on the instance.

    .EXAMPLE
        PS C:\> Find-DbaLoginInGroup -SqlInstance DEV01 | Where-Object Login -like '*stephen*'

        Returns all active directory users within all windows AD groups that have logins on the instance whose login contains "stephen"

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        } catch {
            Stop-Function -Message "Failed to load Assembly needed" -ErrorRecord $_
        }

        function Get-AllLogins {
            param
            (
                [string]$ADGroup,
                [string[]]$discard,
                [string]$ParentADGroup
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
                        $memberDomain = $member.Context.Name
                        if ($member.StructuralObjectClass -eq 'group') {
                            $fullName = $memberDomain + "\" + $member.SamAccountName
                            if ($fullName -in $discard) {
                                Write-Message -Level Verbose -Message "skipping $fullName, already enumerated"
                                continue
                            } else {
                                $subgroups += $fullName
                            }
                        } else {
                            $output += [PSCustomObject]@{
                                SqlInstance        = $server.Name
                                InstanceName       = $server.ServiceName
                                ComputerName       = $server.ComputerName
                                Login              = $memberDomain + "\" + $member.SamAccountName
                                DisplayName        = $member.DisplayName
                                MemberOf           = $AdGroup
                                ParentADGroupLogin = $ParentADGroup
                            }
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to connect to Group: $member." -Target $member -ErrorRecord $_
                }
                $discard += $ADGroup
                foreach ($gr in $subgroups) {
                    if ($gr -notin $discard) {
                        $discard += $gr
                        Write-Message -Level Verbose -Message "Looking at $gr, recursively."
                        Get-AllLogins -ADGroup $gr -discard $discard -ParentADGroup $ParentADGroup
                    }
                }
            }
            end {
                $output
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $AdGroups = $server.Logins | Where-Object { $_.LoginType -eq "WindowsGroup" -and $_.Name -ne "BUILTIN\Administrators" -and $_.Name -notlike "*NT SERVICE*" }

            foreach ($AdGroup in $AdGroups) {
                Write-Message -Level Verbose -Message "Looking at Group: $AdGroup"
                $ADGroupOut += Get-AllLogins $AdGroup.Name -ParentADGroup $AdGroup.Name
            }

            if (-not $Login) {
                $res = $ADGroupOut
            } else {
                $res = $ADGroupOut | Where-Object { $Login -contains $_.Login }
                if ($res.Length -eq 0) {
                    continue
                }
            }
            Select-DefaultView -InputObject $res -Property SqlInstance, Login, DisplayName, MemberOf, ParentADGroupLogin
        }
    }
}