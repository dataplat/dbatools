using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// The Stop-Function call of public/Get-DbaCmObject.ps1 for each way CimService.GetCmObject gives up on a computer:
    /// its message, target, error record, category and switches, so Get-DbaCmObject and every port that calls the pinned
    /// Get-DbaCmObject from inside its own code report one failure the same way (watchman 2ea60ffcdcedcca2).
    /// Get-DbaCmObject passes them to its own Stop-Function; a caller of a nested Get-DbaCmObject -EnableException passes
    /// them to the Stop-Function that nested call throws from.
    /// </summary>
    internal sealed class CmObjectFailureRecord
    {
        /// <summary>The Stop-Function -Message.</summary>
        internal string Message;

        /// <summary>The Stop-Function -Target.</summary>
        internal object Target;

        /// <summary>The Stop-Function -ErrorRecord: the record of the call that failed, as the pin's catch received it.</summary>
        internal ErrorRecord Record;

        /// <summary>The Stop-Function -Category.</summary>
        internal ErrorCategory Category;

        /// <summary>Whether the pin passes -OverrideExceptionMessage.</summary>
        internal bool OverrideExceptionMessage;

        /// <summary>Whether the pin passes its -SilentlyContinue switch on to this Stop-Function.</summary>
        internal bool PassesSilentlyContinue;

        /// <summary>
        /// The Stop-Function call for one failure, or null for a kind the pin has no Stop-Function for.
        /// </summary>
        /// <param name="failure">The failure the observer of GetCmObject received.</param>
        /// <param name="connection">The management connection the run used.</param>
        /// <param name="computer">The lower-case computer name the run used.</param>
        /// <param name="rung">The last rung the observer saw start.</param>
        /// <param name="isClass">Whether the call read a class (the Class parameter set) rather than ran a query.</param>
        /// <param name="className">The call's -ClassName as bound, null for a query.</param>
        /// <param name="cimNamespace">The call's -Namespace as Get-DbaCmObject holds it.</param>
        /// <returns>The Stop-Function call.</returns>
        internal static CmObjectFailureRecord Build(CimService.CmObjectFailure failure, ManagementConnection connection, string computer,
            ManagementConnectionType rung, bool isClass, string className, string cimNamespace)
        {
            if (failure == null)
                throw new ArgumentNullException("failure");

            Exception error = failure.Error;
            string credentialsText = Tagged(computer, "Invalid connection credentials");
            CmObjectFailureRecord report = new CmObjectFailureRecord();
            report.Target = computer;
            report.Category = ErrorCategory.NotSpecified;
            report.PassesSilentlyContinue = true;
            switch (failure.Kind)
            {
                case CimService.CmObjectFailureKind.Credential:
                    // The pin passes no -SilentlyContinue on this one.
                    report.Record = MethodRecord("GetCredential", 1, error);
                    report.Message = failure.Message + report.Record.Exception.Message;
                    report.Target = connection;
                    report.OverrideExceptionMessage = true;
                    report.PassesSilentlyContinue = false;
                    return report;
                case CimService.CmObjectFailureKind.NoConnection:
                    report.Message = Tagged(computer, "Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: " + failure.EnabledProtocols);
                    report.Record = MethodRecord("GetConnectionType", 2, error);
                    report.Category = ErrorCategory.OpenError;
                    return report;
                case CimService.CmObjectFailureKind.CimBadCredentials:
                    // The refusal surfaces where the read does: a class read when the pin's pipeline enumerates it
                    // (measured: BadEnumeration, InvalidOperation), a query inside the method.
                    report.Message = credentialsText;
                    report.Record = CimReadRecord(rung, error, isClass);
                    report.OverrideExceptionMessage = true;
                    return report;
                case CimService.CmObjectFailureKind.CimError:
                    report.Message = failure.Message;
                    report.Record = CimReadRecord(rung, error, isClass);
                    report.OverrideExceptionMessage = true;
                    return report;
                case CimService.CmObjectFailureKind.WmiBadCredentials:
                    report.Message = credentialsText;
                    report.Record = new ErrorRecord(error, error.GetType().Name, ErrorCategory.NotSpecified, null);
                    return report;
                case CimService.CmObjectFailureKind.WmiInvalidClass:
                    // Get-WmiObject rebuilds this error with the class after the provider's text.
#pragma warning disable CA1416
                    System.Management.ManagementException invalidClass = new System.Management.ManagementException(error.Message.TrimEnd() + " \"" + failure.ClassName + "\"");
#pragma warning restore CA1416
                    report.Message = Tagged(computer, "Invalid class name (" + className + "), not found in current namespace (" + cimNamespace + ")");
                    report.Record = new ErrorRecord(invalidClass, "GetWMIManagementException", ErrorCategory.InvalidType, null);
                    return report;
                case CimService.CmObjectFailureKind.WmiProviderLoad:
                    report.Message = Tagged(computer, "Failed to access: " + className + ", in namespace: " + cimNamespace + " - There was a provider error. This indicates a potential issue with WMI on the server side.");
                    report.Record = new ErrorRecord(error, "GetWMIManagementException", ErrorCategory.InvalidOperation, null);
                    return report;
                default:
                    return null;
            }
        }

        private static string Tagged(string computer, string text)
        {
            return String.Concat("[", computer, "] ", text);
        }

        // A class read happens when the pin's pipeline enumerates what the method returned, so the engine
        // reports its failure as a bad enumeration; a query reads its first row inside the method.
        private static ErrorRecord CimReadRecord(ManagementConnectionType rung, Exception error, bool isClass)
        {
            if (!isClass)
                return CimMethodRecord(rung, error, isClass);

            string text = String.Format(CultureInfo.InvariantCulture, "An error occurred while enumerating through a collection: {0}.", error.Message);
            return new ErrorRecord(new RuntimeException(text, error), "BadEnumeration", ErrorCategory.InvalidOperation, null);
        }

        // The pin's CIM calls are .NET method calls, so its error record holds the method's wrapper.
        private static ErrorRecord CimMethodRecord(ManagementConnectionType rung, Exception error, bool isClass)
        {
            string protocol = rung == ManagementConnectionType.CimDCOM ? "CimDCOM" : "CimRM";
            return MethodRecord((isClass ? "Get" : "Query") + protocol + "Instance", isClass ? 3 : 4, error);
        }

        private static ErrorRecord MethodRecord(string method, int argumentCount, Exception error)
        {
            string text = String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, error.Message);
            return new ErrorRecord(new MethodInvocationException(text, error), error.GetType().Name, ErrorCategory.NotSpecified, null);
        }
    }
}
