$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag "UnitTests" {
    $global:object = [PSCustomObject]@{
        Foo  = 42
        Bar  = 18
        Tara = 21
    }
    
    $global:object2 = [PSCustomObject]@{
        Foo    = 42000
        Bar    = 23
    }
    
    $global:list = @()
    $global:list += $object
    $global:list += [PSCustomObject]@{
        Foo   = 23
        Bar   = 88
        Tara  = 28
    }
    
    It "renames Bar to Bar2" {
        ($object | Select-DbaObject -Property 'Foo', 'Bar as Bar2').PSObject.Properties.Name | Should -Be 'Foo', 'Bar2'
    }
    
    It "changes Bar to string" {
        ($object | Select-DbaObject -Property 'Bar to string').Bar.GetType().FullName | Should -Be 'System.String'
    }
    
    it "converts numbers to sizes" {
        ($object2 | Select-DbaObject -Property 'Foo size KB:1').Foo | Should -Be 41
        ($object2 | Select-DbaObject -Property 'Foo size KB:1:1').Foo | Should -Be "41 KB"
    }
    
    it "picks values from other variables" {
        ($object2 | Select-DbaObject -Property 'Tara from object').Tara | Should -Be 21
    }
    
    it "picks values from the properties of the right object in a list" {
        ($object2 | Select-DbaObject -Property 'Tara from List where Foo = Bar').Tara | Should -Be 28
    }
}