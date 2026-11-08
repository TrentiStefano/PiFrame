"""Full-screen neutral backdrop shown behind PiFrame during display recordings."""
import sys, tkinter as tk
color = sys.argv[1] if len(sys.argv) > 1 else '#e8e6e1'
root = tk.Tk()
root.overrideredirect(True)
root.configure(bg=color)
root.geometry(f"{root.winfo_screenwidth()}x{root.winfo_screenheight()}+0+0")
root.lower()
root.mainloop()
