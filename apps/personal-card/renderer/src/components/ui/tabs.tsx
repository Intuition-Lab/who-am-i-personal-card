import { Tabs as TabsPrimitive } from "@base-ui/react/tabs";
import type { ComponentProps } from "react";

export function Tabs(props: ComponentProps<typeof TabsPrimitive.Root>) {
  return <TabsPrimitive.Root {...props} />;
}

export function TabsList(props: ComponentProps<typeof TabsPrimitive.List>) {
  return <TabsPrimitive.List {...props} />;
}

export function TabsTab(props: ComponentProps<typeof TabsPrimitive.Tab>) {
  return <TabsPrimitive.Tab {...props} />;
}

export function TabsPanel(props: ComponentProps<typeof TabsPrimitive.Panel>) {
  return <TabsPrimitive.Panel {...props} />;
}
