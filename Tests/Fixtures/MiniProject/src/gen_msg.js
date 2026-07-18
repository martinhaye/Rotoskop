// Emit a one-line include for the test program.
var text = read("src/message.txt").trim();
print("; generated\n");
print("msg:\n");
print("    .byt " + text.length + ", \"" + text + "\"\n");
