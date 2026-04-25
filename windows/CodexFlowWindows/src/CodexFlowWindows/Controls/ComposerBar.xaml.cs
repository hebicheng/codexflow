using System.Windows.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace CodexFlowWindows.Controls;

public sealed partial class ComposerBar : UserControl
{
    public static readonly DependencyProperty PromptProperty =
        DependencyProperty.Register(nameof(Prompt), typeof(string), typeof(ComposerBar), new PropertyMetadata(string.Empty, OnPromptChanged));

    public static readonly DependencyProperty ButtonTextProperty =
        DependencyProperty.Register(nameof(ButtonText), typeof(string), typeof(ComposerBar), new PropertyMetadata("继续下一步", OnButtonTextChanged));

    public static readonly DependencyProperty SubmitCommandProperty =
        DependencyProperty.Register(nameof(SubmitCommand), typeof(ICommand), typeof(ComposerBar), new PropertyMetadata(null));

    public ComposerBar()
    {
        InitializeComponent();
        PromptBox.TextChanged += (_, _) => Prompt = PromptBox.Text;
        var accelerator = new KeyboardAccelerator
        {
            Key = VirtualKey.Enter,
            Modifiers = VirtualKeyModifiers.Control
        };
        accelerator.Invoked += (_, args) =>
        {
            args.Handled = true;
            ExecuteSubmit();
        };
        KeyboardAccelerators.Add(accelerator);
    }

    public string Prompt
    {
        get => (string)GetValue(PromptProperty);
        set => SetValue(PromptProperty, value);
    }

    public string ButtonText
    {
        get => (string)GetValue(ButtonTextProperty);
        set => SetValue(ButtonTextProperty, value);
    }

    public ICommand? SubmitCommand
    {
        get => (ICommand?)GetValue(SubmitCommandProperty);
        set => SetValue(SubmitCommandProperty, value);
    }

    public void FocusPrompt()
    {
        PromptBox.Focus(FocusState.Programmatic);
    }

    private static void OnPromptChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var control = (ComposerBar)d;
        var text = e.NewValue as string ?? string.Empty;
        if (control.PromptBox.Text != text)
        {
            control.PromptBox.Text = text;
        }
    }

    private static void OnButtonTextChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((ComposerBar)d).SubmitButton.Content = e.NewValue as string ?? "继续下一步";
    }

    private void SubmitClicked(object sender, RoutedEventArgs e)
    {
        ExecuteSubmit();
    }

    private void ExecuteSubmit()
    {
        if (SubmitCommand?.CanExecute(null) == true)
        {
            SubmitCommand.Execute(null);
        }
    }
}
