# Parameter & Variable Naming Rules

## Parameter Usage Guidelines
- Use direct parameters for 1-2 parameters
- Use `$splat<Purpose>` for 3+ parameters (never plain `$splat`)
- Align splat hashtable assignments with consistent spacing for readability

```powershell
# Direct parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix - note aligned = signs
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}
$primaryAg = New-DbaAvailabilityGroup @splatPrimary
```

## Unique Names Across Scopes
Use unique, descriptive variable names across scopes to avoid collisions. Pay particular attention to variable names in BeforeAll:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name    = $primaryAgName
            ...
        }
        $ag = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name    = $replicaAgName
                ...
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```