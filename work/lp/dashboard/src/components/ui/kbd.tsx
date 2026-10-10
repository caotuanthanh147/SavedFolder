import * as React from "react"
import { cn } from "cn"

function Kbd({ className, ...props }: React.ComponentProps<"kbd">) {
  return (
    <kbd
      data-slot="kbd"
      className={cn(
        "pointer-events-none inline-flex h-5 select-none items-center rounded border px-1.5 font-mono text-[10px] font-medium text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}

export { Kbd }
