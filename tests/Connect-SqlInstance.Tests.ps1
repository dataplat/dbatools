$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    $password = 'MyV3ry$ecur3P@ssw0rd'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $server = Connect-SqlInstance -SqlInstance $script:instance1
    $login = "csitester"

    #Cleanup

    $results = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'"
    foreach ($spid in $results.spid) {
        Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "kill $spid"
    }

    if ($l = $server.logins[$login]) {
        if ($c = $l.EnumCredentials()) {
            $l.DropCredential($c)
        }
        $l.Drop()
    }

    #Create login
    $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $login)
    $newLogin.LoginType = "SqlLogin"
    $newLogin.Create($password)

    Context "Connect with a new login" {
        It "Should login with newly created Sql Login (also tests credential login) and get instance name" {
            $cred = New-Object System.Management.Automation.PSCredential ($login, $securePassword)
            $s = Connect-SqlInstance -SqlInstance $script:instance1 -SqlCredential $cred
            $s.Name | Should Be $script:instance1
        }
        It "Should return existing process running under the new login and kill it" {
            $results = Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$login') EXEC sp_who '$login'"
            $results | Should Not BeNullOrEmpty
            foreach ($spid in $results.spid) {
                { Invoke-Sqlcmd2 -ServerInstance $script:instance1 -Query "kill $spid" -ErrorAction Stop} | Should Not Throw
            }
        }
    }

    #Cleanup
    if ($l = $server.logins[$login]) {
        if ($c = $l.EnumCredentials()) {
            $l.DropCredential($c)
        }
        $l.Drop()
    }
}