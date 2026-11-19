using System;
using System.Management.Automation;
using System.Text;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>Preserves the Server.Query adapter's exception chain and method-binder text.</summary>
    public static class NativeServerQuery
    {
        public static MethodInvocationException QueryMethodException(Exception failure)
        {
            StringBuilder message = new StringBuilder();
            Exception current = failure;
            while (current.InnerException != null)
            {
                message.Append(current.Message);
                current = current.InnerException;
            }
            message.Append(current.Message);
            string text = "Exception calling \"Query\" with \"1\" argument(s): \"" + message + "\"";
            return new MethodInvocationException(text, new RuntimeException(message.ToString(), failure));
        }
    }
}
