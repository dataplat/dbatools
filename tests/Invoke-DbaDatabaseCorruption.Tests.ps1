$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tags "UnitTests" {
  Context "Validating Database Input" {
    It "Should not allow you to corrupt system databases."{
      {
        Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database "master"
      } | Should Throw
    }
    It "Should fail if more than one database is specified" {
      {
        Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database "Database1","Database2"
      } | Should Throw
    }
  }

  Context "It's Confirm impact should be high" {
    $command = Get-Command Invoke-DbaDatabaseCorruption
    $metadata = [System.Management.Automation.CommandMetadata]$command
    $metadata.ConfirmImpact | Should Be 'High'
  }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
  $Uniqueifier = New-Guid
  $db = "InvokeDbaDatabaseCorruptionTest"
  $Server = Connect-DbaSqlServer -SqlInstance $script:instance1

  # Need a clean empty database
  $null = $Server.Query("Create Database [$db]")

  Context "Require at least a single table in the database specified" {
    {
      Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database $db
    } | Should Throw
  }

  # Creating a table to make sure these are failing for different reasons
  $null = $Server.Query ("Create table dbo.[Example] ( id int identity );")
  Context "Fail if the specified table does not exist" {
    {
      Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database $db -Table "DoesntExist$Uniqueifier"
    } | Should Throw
  }

  # Could test this in a few ways
  Context "Corrupt a single database" {
    Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database $db | Select-Object Status | Should be "Corrupted"
    Backup-DbaDatabase -SqlInstance $script:instance1 -Verify -Database $db | Select-Object Verified | Should be $false
  }

  # Cleanup
  $Server.Query("Drop Database [$db]")
}