using System;
using System.Collections.Generic;
using System.Linq;
using System.Security;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Dedicated class to prompt for credentials
    /// </summary>
    public class CredentialPrompt
    {
        /// <summary>
        /// The name of the user to pre-fill the username field
        /// </summary>
        public string Name;

        /// <summary>
        /// The window of the prompt that was shown
        /// </summary>
        public Window Window;

        private PasswordBox password;

        /// <summary>
        /// The final, resulting username
        /// </summary>
        public string Username;

        /// <summary>
        /// The final, result password
        /// </summary>
        public SecureString Password;

        /// <summary>
        /// Whether the password should be remembered
        /// </summary>
        public bool Remember;

        /// <summary>
        /// Marker indicating that execution has finished
        /// </summary>
        public bool Finished = false;

        /// <summary>
        /// Whether the windoww was cancelled
        /// </summary>
        public bool Cancelled = false;

        /// <summary>
        /// Start asking away
        /// </summary>
        public void PromptForCredential()
        {
            Window window = new Window();
            window.Name = "MainWindow";
            window.Title = "Enter Credentials";
            window.Height = 210;
            window.Width = 300;
            window.Icon = null;
            window.Loaded += window_loaded;
            this.Window = window;

            Grid grid = new Grid();
            window.Content = grid;

            Label label_username = new Label();
            label_username.Content = "Username";
            label_username.Margin = new Thickness(10, 10, 0, 0);
            label_username.VerticalAlignment = VerticalAlignment.Top;
            label_username.HorizontalAlignment = HorizontalAlignment.Left;
            label_username.Height = 23;
            label_username.VerticalContentAlignment = VerticalAlignment.Bottom;
            label_username.HorizontalContentAlignment = HorizontalAlignment.Left;
            grid.Children.Add(label_username);

            TextBox tb_username = new TextBox();
            tb_username.Name = "tb_username";
            tb_username.Text = Name;
            tb_username.Margin = new Thickness(10, 33, 10, 0);
            tb_username.Height = 30;
            tb_username.BorderThickness = new Thickness(2);
            tb_username.VerticalAlignment = VerticalAlignment.Top;
            tb_username.VerticalContentAlignment = VerticalAlignment.Center;
            tb_username.HorizontalContentAlignment = HorizontalAlignment.Center;
            grid.Children.Add(tb_username);

            Label label_password = new Label();
            label_password.Content = "Password";
            label_password.Margin = new Thickness(10, 68, 0, 0);
            label_password.VerticalAlignment = VerticalAlignment.Top;
            label_password.HorizontalAlignment = HorizontalAlignment.Left;
            label_password.Height = 23;
            label_password.VerticalContentAlignment = VerticalAlignment.Bottom;
            label_password.HorizontalContentAlignment = HorizontalAlignment.Left;
            grid.Children.Add(label_password);

            PasswordBox tb_password = new PasswordBox();
            tb_password.Name = "tb_password";
            tb_password.Margin = new Thickness(10, 91, 10, 0);
            tb_password.Height = 30;
            tb_password.BorderThickness = new Thickness(2);
            tb_password.VerticalAlignment = VerticalAlignment.Top;
            tb_password.VerticalContentAlignment = VerticalAlignment.Center;
            tb_password.HorizontalContentAlignment = HorizontalAlignment.Center;
            grid.Children.Add(tb_password);
            password = tb_password;

            CheckBox cb_remember = new CheckBox();
            cb_remember.Name = "cb_remember";
            cb_remember.Content = "Remember Password";
            cb_remember.HorizontalAlignment = HorizontalAlignment.Left;
            cb_remember.Margin = new Thickness(10, 126, 0, 0);
            cb_remember.VerticalAlignment = VerticalAlignment.Top;
            grid.Children.Add(cb_remember);
            
            Button b_ok = new Button();
            b_ok.Name = "b_ok";
            b_ok.Content = "OK";
            b_ok.Margin = new Thickness(10, 150, 0, 0);
            b_ok.HorizontalAlignment = HorizontalAlignment.Left;
            b_ok.VerticalAlignment = VerticalAlignment.Top;
            b_ok.Width = 75;
            b_ok.IsDefault = true;
            b_ok.Click += button_ok_Click;
            grid.Children.Add(b_ok);

            Button b_cancel = new Button();
            b_cancel.Name = "b_cancel";
            b_cancel.Content = "Cancel";
            b_cancel.Margin = new Thickness(0, 150, 10, 0);
            b_cancel.HorizontalAlignment = HorizontalAlignment.Right;
            b_cancel.VerticalAlignment = VerticalAlignment.Top;
            b_cancel.Width = 75;
            b_cancel.IsCancel = true;
            b_cancel.Click += button_cancel_Click;
            grid.Children.Add(b_cancel);

            try
            {
                window.ShowDialog();
                Username = tb_username.Text;
                Password = tb_password.SecurePassword;
                Remember = (bool)cb_remember.IsChecked;
            }
            catch { }
            Finished = true;
        }

        #region EventHandler
        private void button_ok_Click(object sender, RoutedEventArgs e)
        {
            Window.Close();
        }

        private void button_cancel_Click(object sender, RoutedEventArgs e)
        {
            Cancelled = true;
        }
        
        private void window_loaded(object sender, EventArgs e)
        {
            Window.Activate();
            password.Focus();
        }
        #endregion EventHandler

        /// <summary>
        /// Executes a request for credentials on a dedicated STA thread
        /// </summary>
        /// <param name="Name">THe name of the user to put in the prompt</param>
        /// <returns>The result object</returns>
        public static CredentialPrompt GetCredential(string Name)
        {
            CredentialPrompt temp = new CredentialPrompt();
            temp.Name = Name;
            Thread thread = new Thread(new ThreadStart(temp.PromptForCredential));
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            while (!thread.IsAlive)
                Thread.Sleep(1);
            thread.Join();
            return temp;
        }
    }
}
