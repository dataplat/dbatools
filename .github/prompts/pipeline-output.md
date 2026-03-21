# Pipeline Output Patterns

**CRITICAL RULE**: NEVER collect objects in an ArrayList or array and output them at the end. Output objects to the pipeline immediately as they are created.

## Why Immediate Output

- **Memory Efficiency**: Objects are released to the pipeline immediately, not held in memory
- **User Experience**: Users see results streaming in real-time, not waiting until the end
- **Pipeline Compatibility**: Enables proper pipeline chaining and early termination (Ctrl+C)
- **Error Resilience**: Partial results are available even if the command fails partway through

## Correct Pattern - Output Immediately

```powershell
foreach ($instance in $SqlInstance) {
    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential

    foreach ($db in $server.Databases) {
        # Output each object immediately to the pipeline
        [PSCustomObject]@{
            ComputerName = $server.ComputerName
            InstanceName = $server.ServiceName
            SqlInstance  = $server.DomainInstanceName
            Database     = $db.Name
            Size         = $db.Size
        }
    }
}
```

## Wrong Patterns - DO NOT USE

### ArrayList Collection (OLD PATTERN)

```powershell
# WRONG - This is an outdated anti-pattern
$results = New-Object System.Collections.ArrayList

foreach ($instance in $SqlInstance) {
    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential

    foreach ($db in $server.Databases) {
        $null = $results.Add([PSCustomObject]@{
            ComputerName = $server.ComputerName
            Database     = $db.Name
        })
    }
}

# WRONG - Holding everything until the end
$results
```

### Array Concatenation (Worst Performance)

```powershell
# WRONG - Array concatenation is extremely slow
$results = @()

foreach ($db in $databases) {
    $results += [PSCustomObject]@{
        Name = $db.Name
    }
}

$results
```

## No -Detailed or -Simple Parameters

Do NOT create `-Detailed` or `-Simple` switch parameters that change the output object structure. This is an outdated pattern that creates confusion and breaks pipeline expectations.

```powershell
# WRONG - Do not create output mode switches
param(
    [switch]$Detailed,
    [switch]$Simple
)

if ($Detailed) {
    # Return more properties
} elseif ($Simple) {
    # Return fewer properties
}
```

Instead, return a consistent object with all relevant properties. Users can select the properties they want with `Select-Object`.

## Process Block Pattern

When using `ValueFromPipeline`, output in the `process` block, not `end`:

```powershell
function Get-DbaExample {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    process {
        foreach ($instance in $SqlInstance) {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential

            foreach ($item in $server.SomeCollection) {
                # Output immediately in process block
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Name         = $item.Name
                }
            }
        }
    }
}
```

## Summary

- Output objects immediately as they are created
- Never use ArrayList, Generic.List, or array += to collect results
- Never use `-Detailed`/`-Simple` output mode switches
- Process pipeline input in the `process` block, not `end`
- Let PowerShell's pipeline handle the collection if the user needs it
