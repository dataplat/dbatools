# Prompt for AI to analyze PowerShell command output columns

You are analyzing a PowerShell command file to document its output properties/columns.

## Task
Review the provided PowerShell command code and identify all output properties/columns that are returned to the user.

## Instructions

1. **Trace all execution paths** including:
   - Default output
   - Switch parameters that modify output (like -Detailed, -Simple, -Raw, etc.)
   - Conditional logic that changes what's returned
   - Different outputs for different input types

2. **For each execution path, identify**:
   - The complete list of property names
   - The data type of each property (string, int, bool, datetime, custom object, etc.)
   - A brief description of what each property contains
   - Which path(s) return this property set

3. **Focus on user-visible output**:
   - Properties added via `Select-Object`, `Add-Member`, or PSCustomObject creation
   - Properties from objects being passed through or returned
   - Ignore internal/private variables not included in output

4. **Handle common dbatools patterns**:
   - `Select-DefaultView` - note which properties are shown by default vs available
   - Pipeline objects with added properties
   - Different object types returned based on conditions

## Output Format

Return a JSON structure like this:
```json
{
  "defaultOutput": {
    "properties": [
      {
        "name": "PropertyName",
        "type": "string",
        "description": "What this property contains"
      }
    ],
    "notes": "Any important context about default output"
  },
  "paths": [
    {
      "trigger": "-Detailed switch",
      "properties": [
        {
          "name": "AdditionalProperty",
          "type": "int",
          "description": "Only returned with -Detailed"
        }
      ],
      "notes": "Additional context for this path"
    }
  ],
  "selectDefaultView": {
    "defaultProperties": ["Prop1", "Prop2"],
    "allAvailableProperties": ["Prop1", "Prop2", "Prop3", "Prop4"]
  }
}
```

## Code to analyze:

[PASTE COMMAND CODE HERE]