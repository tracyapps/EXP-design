import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App.jsx";
import {AccountSessionProvider} from './AccountSession.jsx';
import "./styles.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AccountSessionProvider><App /></AccountSessionProvider>
  </React.StrictMode>,
);
