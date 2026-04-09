import AppKit

final class iTermBridge {
    static func send(prompt: String, context: String?) {
        var templateParts: [String] = []
        if let context = context, !context.isEmpty {
            templateParts.append("Given this context:\\n\(escapeForShell(context))\\n\\nTask: \(escapeForShell(prompt))")
        } else {
            templateParts.append(escapeForShell(prompt))
        }
        let fullPrompt = templateParts.joined()

        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
                tell current session of current window
                    write text "/opt/homebrew/bin/claude --dangerously-skip-permissions \\\"\(escapeForAppleScript(fullPrompt))\\\""
                end tell
            else
                tell current window
                    create tab with default profile
                    tell current session
                        write text "/opt/homebrew/bin/claude --dangerously-skip-permissions \\\"\(escapeForAppleScript(fullPrompt))\\\""
                    end tell
                end tell
            end if
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            if let error = error {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Failed to send to iTerm"
                    alert.informativeText = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    alert.runModal()
                }
            }
        }
    }

    private static func escapeForShell(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "$", with: "\\$")
         .replacingOccurrences(of: "`", with: "\\`")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
