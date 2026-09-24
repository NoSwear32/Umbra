export type Status = "Active" | "Complete" | "Processing";
export type ModuleName = "Orb" | "Sage" | "Manic Heart";

export interface ActivityRow {
  id: string;
  activity: string;
  module: ModuleName;
  status: Status;
  date: string;
  details: string;
}

export const activityRows: ActivityRow[] = [
  {
    id: "A-1042",
    activity: "Deep focus session completed",
    module: "Orb",
    status: "Complete",
    date: "Today, 2:14 PM",
    details: "42 min · 3 goals cleared",
  },
  {
    id: "A-1041",
    activity: "Weekly insight digest generated",
    module: "Sage",
    status: "Complete",
    date: "Today, 1:02 PM",
    details: "7 insights · 2 flagged",
  },
  {
    id: "A-1040",
    activity: "Pulse anomaly review",
    module: "Manic Heart",
    status: "Processing",
    date: "Today, 11:47 AM",
    details: "Awaiting signal confirmation",
  },
  {
    id: "A-1039",
    activity: "Ambient workspace sync",
    module: "Orb",
    status: "Active",
    date: "Today, 10:30 AM",
    details: "3 devices connected",
  },
  {
    id: "A-1038",
    activity: "Conversation summarized",
    module: "Sage",
    status: "Complete",
    date: "Yesterday, 8:52 PM",
    details: "14 messages · saved to notes",
  },
  {
    id: "A-1037",
    activity: "Signal calibration",
    module: "Manic Heart",
    status: "Complete",
    date: "Yesterday, 6:10 PM",
    details: "Baseline updated",
  },
  {
    id: "A-1036",
    activity: "Session handoff to Sage",
    module: "Orb",
    status: "Processing",
    date: "Yesterday, 4:44 PM",
    details: "Context transfer in progress",
  },
];

export interface NotificationItem {
  id: string;
  title: string;
  body: string;
  time: string;
  read: boolean;
  kind: "orb" | "sage" | "heart" | "system";
}

export const notifications: NotificationItem[] = [
  {
    id: "N-1",
    title: "Sage found a new pattern",
    body: "Your focus peaks between 9–11 AM this week.",
    time: "3m ago",
    read: false,
    kind: "sage",
  },
  {
    id: "N-2",
    title: "Orb session complete",
    body: "42 minute deep session logged successfully.",
    time: "1h ago",
    read: false,
    kind: "orb",
  },
  {
    id: "N-3",
    title: "Manic Heart pulse stable",
    body: "Signal variance back within normal range.",
    time: "3h ago",
    read: true,
    kind: "heart",
  },
  {
    id: "N-4",
    title: "Weekly summary ready",
    body: "Your productivity digest for last week is ready to view.",
    time: "Yesterday",
    read: true,
    kind: "system",
  },
  {
    id: "N-5",
    title: "New device connected",
    body: "A new device signed in to your Umbra account.",
    time: "2 days ago",
    read: true,
    kind: "system",
  },
];

export interface ModuleUsageItem {
  name: ModuleName;
  percent: number;
  sessions: number;
  color: string;
}

export const moduleUsage: ModuleUsageItem[] = [
  { name: "Orb", percent: 68, sessions: 128, color: "#16D5D5" },
  { name: "Sage", percent: 52, sessions: 94, color: "#23D98A" },
  { name: "Manic Heart", percent: 31, sessions: 47, color: "#E8B95E" },
];

export const orbSessions = [
  { id: "S-901", label: "Deep focus · Design review", duration: "42 min", when: "Today, 2:14 PM" },
  { id: "S-900", label: "Ambient · Writing sprint", duration: "28 min", when: "Today, 9:05 AM" },
  { id: "S-899", label: "Deep focus · Planning", duration: "55 min", when: "Yesterday, 5:40 PM" },
  { id: "S-898", label: "Ambient · Inbox sweep", duration: "16 min", when: "Yesterday, 11:02 AM" },
];

export const sageInsights = [
  {
    id: "I-401",
    title: "Focus is trending upward",
    body: "Your average deep-work block grew 18% this week, mostly in the morning window.",
    tag: "Trend",
  },
  {
    id: "I-400",
    title: "Context switching spike detected",
    body: "Tuesday afternoon showed 3x your usual app-switch rate — consider batching messages.",
    tag: "Alert",
  },
  {
    id: "I-399",
    title: "Weekly reflection ready",
    body: "Sage drafted a short reflection based on your notes from the last 7 days.",
    tag: "Digest",
  },
];

export const sageConversations = [
  { id: "C-12", title: "Q3 roadmap brainstorm", time: "2h ago", messages: 24 },
  { id: "C-11", title: "Debugging onboarding drop-off", time: "Yesterday", messages: 11 },
  { id: "C-10", title: "Morning journal reflection", time: "2 days ago", messages: 6 },
  { id: "C-9", title: "Hiring plan notes", time: "4 days ago", messages: 18 },
];

export const heartHistory = [
  { id: "H-88", label: "Evening wind-down", state: "Stable", when: "Today, 9:40 PM", value: 62 },
  { id: "H-87", label: "Midday check-in", state: "Elevated", when: "Today, 1:15 PM", value: 84 },
  { id: "H-86", label: "Morning baseline", state: "Stable", when: "Today, 7:30 AM", value: 58 },
  { id: "H-85", label: "Late night session", state: "Stable", when: "Yesterday, 11:50 PM", value: 60 },
];

export const activityTrend = [24, 30, 22, 38, 44, 36, 52, 48, 61, 55, 70, 66];

export const user = {
  name: "Mahir Sakovic",
  handle: "@mahir",
  email: "sakovic.mahir32@gmail.com",
  plan: "Umbra Pro",
  status: "Active",
  avatarInitials: "MS",
  memberSince: "March 2024",
};
