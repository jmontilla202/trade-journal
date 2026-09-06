import {
  type ChangeEvent,
  type FormEvent,
  useEffect,
  useMemo,
  useState,

} from "react";


import { api } from "./api";
import {
  clearDraft,
  loadDraft,
  saveDraft,

} from "./draftStore";

import type {
  Account,
  Instrument,
  Trade,
  TradeForm,
} from "./types";

function localDate(): string {
  const date = new Date();
  const offset = date.getTimezoneOffset() * 60_000;

  return new Date(date.getTime() - offset)
    .toISOString()
    .slice(0, 10);
}

function localDateTime(value = new Date()): string {
  const offset = value.getTimezoneOffset() * 60_000;

  return new Date(value.getTime() - offset)
    .toISOString()

    .slice(0, 16);
}

function initialForm(): TradeForm {
  return {
    sessionDate: localDate(),
    accountId: "",

    instrument: "ES",
    direction: "LONG",
    contracts: "1",
    entryTime: localDateTime(),
    entryPrice: "",

    initialStopPrice: "",
    initialStopReference: "",
    plannedTargetPrice: "",
    plannedTargetReference: "",

    setup: "",
    primaryLocation: "",
    secondaryLocation: "",
    trigger: "",
    notes: "",
  };
}

function tradeToForm(trade: Trade): TradeForm {
  return {

    sessionDate: trade.sessionDate,
    accountId: trade.account?.id ?? "",
    instrument: trade.instrument?.symbol ?? "",
    direction: trade.direction ?? "LONG",
    contracts: trade.contracts?.toString() ?? "",
    entryTime: trade.entryTime

      ? localDateTime(new Date(trade.entryTime))
      : "",
    entryPrice: trade.entryPrice?.toString() ?? "",
    initialStopPrice:
      trade.initialStopPrice?.toString() ?? "",
    initialStopReference:
      trade.initialStopReference ?? "",
    plannedTargetPrice:
      trade.plannedTargetPrice?.toString() ?? "",
    plannedTargetReference:

      trade.plannedTargetReference ?? "",
    setup: trade.setup ?? "",
    primaryLocation: trade.primaryLocation ?? "",
    secondaryLocation: trade.secondaryLocation ?? "",
    trigger: trade.trigger ?? "",
    notes: trade.notes ?? "",
  };
}

function currency(value: number | null): string {
  if (value === null) {
    return "—";
  }

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(value);
}

function decimal(value: number | null, places = 2): string {
  if (value === null) {
    return "—";
  }

  return value.toFixed(places);
}

export default function App() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [instruments, setInstruments] = useState<Instrument[]>(
    [],
  );
  const [trades, setTrades] = useState<Trade[]>([]);

  const [form, setForm] = useState<TradeForm>(initialForm);
  const [draftID, setDraftID] = useState<string | null>(null);
  const [restored, setRestored] = useState(false);

  const [closingTrade, setClosingTrade] =
    useState<Trade | null>(null);
  const [exitTime, setExitTime] = useState(localDateTime);
  const [exitPrice, setExitPrice] = useState("");

  const [fees, setFees] = useState("0");

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function refreshTrades() {
    setTrades(await api.listTrades());
  }

  useEffect(() => {

    async function initialize() {
      try {
        const [accountData, instrumentData, tradeData, stored] =
          await Promise.all([
            api.listAccounts(),
            api.listInstruments(),
            api.listTrades(),
            loadDraft(),
          ]);


        setAccounts(accountData);

        setInstruments(instrumentData);
        setTrades(tradeData);

        if (stored) {
          setForm(stored.form);
          setDraftID(stored.id);
        } else {
          setForm((current) => ({
            ...current,
            accountId: accountData[0]?.id ?? "",
            instrument: instrumentData[0]?.symbol ?? "ES",

          }));
        }
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message

            : "Failed to initialize application",

        );
      } finally {
        setRestored(true);
        setLoading(false);
      }
    }


    void initialize();
  }, []);

  useEffect(() => {
    if (!restored) {
      return;
    }

    const timeout = window.setTimeout(() => {

      void saveDraft({
        id: draftID,
        form,
      });
    }, 300);

    return () => window.clearTimeout(timeout);
  }, [draftID, form, restored]);

  const openTrades = useMemo(
    () => trades.filter((trade) => trade.status === "OPEN"),
    [trades],
  );

  const closedNetPnl = useMemo(
    () =>
      trades

        .filter((trade) => trade.status === "CLOSED")
        .reduce((sum, trade) => sum + (trade.netPnl ?? 0), 0),
    [trades],
  );

  function updateField(
    event: ChangeEvent<
      HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement
    >,

  ) {
    const { name, value } = event.target;


    setForm((current) => ({

      ...current,
      [name]: value,
    }));
  }

  function clearMessages() {
    setError("");
    setMessage("");
  }

  function resetForm() {
    const next = initialForm();

    next.accountId = accounts[0]?.id ?? "";

    next.instrument = instruments[0]?.symbol ?? "ES";

    setForm(next);
    setDraftID(null);
    void clearDraft();
  }

  async function persistDraft(): Promise<Trade> {
    if (draftID) {
      return api.updateDraft(draftID, form);

    }

    const trade = await api.createDraft(form);

    setDraftID(trade.id);

    return trade;
  }

  async function handleSaveDraft(event: FormEvent) {
    event.preventDefault();
    clearMessages();
    setSaving(true);

    try {
      const trade = await persistDraft();

      await saveDraft({
        id: trade.id,
        form,
      });

      await refreshTrades();
      setMessage("Draft saved");
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Failed to save draft",
      );
    } finally {
      setSaving(false);

    }
  }


  async function handleOpenTrade() {
    clearMessages();
    setSaving(true);

    try {
      const draft = await persistDraft();
      const opened = await api.openTrade(draft.id);

      resetForm();
      await refreshTrades();


      setMessage(
        `Trade ${opened.tradeId ?? opened.id} is open`,
      );
    } catch (cause) {
      setError(
        cause instanceof Error

          ? cause.message
          : "Failed to open trade",
      );
    } finally {
      setSaving(false);
    }
  }

  function editDraft(trade: Trade) {
    setDraftID(trade.id);
    setForm(tradeToForm(trade));
    setMessage("Draft loaded for editing");
    setError("");

    window.scrollTo({
      top: 0,
      behavior: "smooth",
    });
  }

  function beginClose(trade: Trade) {
    setClosingTrade(trade);

    setExitTime(localDateTime());
    setExitPrice("");
    setFees("0");
    clearMessages();
  }

  async function handleCloseTrade(event: FormEvent) {
    event.preventDefault();


    if (!closingTrade) {
      return;
    }

    clearMessages();
    setSaving(true);

    try {
      const closed = await api.closeTrade(
        closingTrade.id,
        exitTime,
        exitPrice,
        fees,
      );


      setClosingTrade(null);
      await refreshTrades();


      setMessage(
        `${closed.tradeId ?? "Trade"} closed: ${currency(
          closed.netPnl,
        )}`,
      );

    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Failed to close trade",
      );
    } finally {
      setSaving(false);
    }

  }

  if (loading) {

    return <main className="loading">Loading journal…</main>;

  }

  return (

    <main className="app-shell">

      <header className="page-header">
        <div>

          <p className="eyebrow">Futures trade journal</p>
          <h1>Quick Capture</h1>
          <p className="subtitle">
            Capture the trade first. Analyze it when the market
            stops throwing furniture.
          </p>
        </div>

        <div className="summary">
          <div>
            <span>Open trades</span>
            <strong>{openTrades.length}</strong>

          </div>

          <div>
            <span>Recorded trades</span>
            <strong>{trades.length}</strong>
          </div>

          <div>
            <span>Closed net P&amp;L</span>
            <strong
              className={

                closedNetPnl >= 0 ? "positive" : "negative"
              }
            >
              {currency(closedNetPnl)}
            </strong>
          </div>
        </div>
      </header>

      {error && (
        <div className="notice error" role="alert">

          {error}
        </div>
      )}

      {message && (
        <div className="notice success" role="status">
          {message}
        </div>
      )}

      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>{draftID ? "Edit draft" : "New trade"}</h2>

            <p>
              Drafts are also preserved locally in this browser.

            </p>
          </div>

          {draftID && (
            <button
              className="button secondary"
              type="button"
              onClick={resetForm}
            >
              New trade

            </button>
          )}
        </div>

        <form onSubmit={handleSaveDraft}>
          <div className="form-grid">
            <label>
              <span>Session date</span>

              <input

                required
                type="date"
                name="sessionDate"
                value={form.sessionDate}
                onChange={updateField}
              />
            </label>

            <label>
              <span>Account</span>
              <select
                name="accountId"
                value={form.accountId}
                onChange={updateField}

              >
                <option value="">Select account</option>


                {accounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.name}
                  </option>
                ))}
              </select>

            </label>

            <label>
              <span>Instrument</span>
              <select
                name="instrument"

                value={form.instrument}
                onChange={updateField}
              >
                <option value="">Select instrument</option>

                {instruments.map((instrument) => (
                  <option
                    key={instrument.symbol}
                    value={instrument.symbol}
                  >
                    {instrument.symbol} — {instrument.name}
                  </option>
                ))}
              </select>
            </label>


            <label>
              <span>Direction</span>
              <select
                name="direction"
                value={form.direction}
                onChange={updateField}
              >
                <option value="LONG">Long</option>
                <option value="SHORT">Short</option>
              </select>
            </label>


            <label>
              <span>Contracts</span>
              <input
                type="number"
                min="1"
                step="1"
                name="contracts"
                value={form.contracts}
                onChange={updateField}
              />

            </label>

            <label>
              <span>Entry time</span>
              <input
                type="datetime-local"
                name="entryTime"
                value={form.entryTime}
                onChange={updateField}
              />
            </label>

            <label>
              <span>Entry price</span>
              <input
                inputMode="decimal"
                type="number"
                min="0"
                step="0.01"
                name="entryPrice"
                value={form.entryPrice}
                onChange={updateField}
                placeholder="7722.25"
              />
            </label>

            <label>
              <span>Initial stop</span>
              <input
                inputMode="decimal"
                type="number"
                min="0"

                step="0.01"

                name="initialStopPrice"
                value={form.initialStopPrice}
                onChange={updateField}
              />
            </label>

            <label>
              <span>Stop reference</span>
              <input

                name="initialStopReference"
                value={form.initialStopReference}
                onChange={updateField}
                placeholder="POC, swing high, structure"
              />
            </label>

            <label>
              <span>Planned target</span>
              <input

                inputMode="decimal"
                type="number"
                min="0"
                step="0.01"
                name="plannedTargetPrice"
                value={form.plannedTargetPrice}
                onChange={updateField}
              />
            </label>

            <label>
              <span>Target reference</span>
              <input
                name="plannedTargetReference"
                value={form.plannedTargetReference}
                onChange={updateField}

                placeholder="IBH, IBL, prior high"
              />
            </label>

            <label>
              <span>Setup</span>
              <input
                name="setup"
                value={form.setup}
                onChange={updateField}
                placeholder="Trend 2ES"
              />
            </label>

            <label>
              <span>Primary location</span>
              <input
                name="primaryLocation"

                value={form.primaryLocation}
                onChange={updateField}
                placeholder="VAL"

              />
            </label>


            <label>
              <span>Secondary location</span>
              <input
                name="secondaryLocation"
                value={form.secondaryLocation}
                onChange={updateField}
                placeholder="EMA21"
              />
            </label>

            <label>
              <span>Trigger</span>
              <input
                name="trigger"
                value={form.trigger}
                onChange={updateField}
                placeholder="Reversal bar"
              />
            </label>

            <label className="full-width">
              <span>Notes</span>
              <textarea
                name="notes"

                rows={3}
                value={form.notes}
                onChange={updateField}
                placeholder="Context, thesis, execution notes"
              />
            </label>
          </div>

          <div className="form-actions">
            <button
              className="button secondary"
              type="submit"
              disabled={saving}
            >
              Save draft
            </button>

            <button
              className="button primary"
              type="button"
              disabled={saving}

              onClick={() => void handleOpenTrade()}
            >
              Save &amp; open trade
            </button>
          </div>
        </form>
      </section>

      {closingTrade && (
        <section className="panel close-panel">
          <div className="panel-heading">
            <div>
              <h2>Close {closingTrade.tradeId}</h2>
              <p>
                {closingTrade.direction}{" "}
                {closingTrade.contracts}{" "}
                {closingTrade.instrument?.symbol} from{" "}
                {closingTrade.entryPrice}
              </p>
            </div>

            <button
              className="button secondary"
              type="button"
              onClick={() => setClosingTrade(null)}
            >
              Cancel
            </button>
          </div>

          <form onSubmit={handleCloseTrade}>
            <div className="form-grid close-grid">
              <label>
                <span>Exit time</span>
                <input
                  required
                  type="datetime-local"
                  value={exitTime}
                  onChange={(event) =>

                    setExitTime(event.target.value)
                  }
                />
              </label>

              <label>
                <span>Exit price</span>
                <input

                  required
                  autoFocus
                  type="number"

                  min="0"
                  step="0.01"

                  value={exitPrice}
                  onChange={(event) =>
                    setExitPrice(event.target.value)
                  }
                />
              </label>

              <label>
                <span>Fees</span>
                <input
                  required
                  type="number"
                  min="0"
                  step="0.01"
                  value={fees}
                  onChange={(event) =>
                    setFees(event.target.value)
                  }
                />
              </label>
            </div>


            <div className="form-actions">
              <button
                className="button danger"
                type="submit"
                disabled={saving}
              >

                Close trade
              </button>
            </div>
          </form>

        </section>
      )}

      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>Recent trades</h2>
            <p>Latest 100 trades across all sessions.</p>
          </div>

          <button
            className="button secondary"
            type="button"
            onClick={() => void refreshTrades()}
          >
            Refresh
          </button>
        </div>

        <div className="table-wrapper">
          <table>
            <thead>
              <tr>
                <th>Trade</th>
                <th>Status</th>

                <th>Market</th>
                <th>Direction</th>
                <th>Entry</th>
                <th>Exit</th>
                <th>Risk</th>
                <th>Net P&amp;L</th>
                <th>R</th>
                <th aria-label="Actions" />
              </tr>
            </thead>

            <tbody>
              {trades.map((trade) => (

                <tr key={trade.id}>
                  <td>
                    <strong>
                      {trade.tradeId ?? "Unnumbered draft"}
                    </strong>
                    <small>{trade.sessionDate}</small>
                  </td>

                  <td>

                    <span
                      className={`status ${trade.status.toLowerCase()}`}
                    >
                      {trade.status}
                    </span>
                  </td>


                  <td>
                    {trade.contracts ?? "—"}{" "}
                    {trade.instrument?.symbol ?? "—"}
                  </td>

                  <td>{trade.direction ?? "—"}</td>
                  <td>{decimal(trade.entryPrice)}</td>
                  <td>{decimal(trade.exitPrice)}</td>
                  <td>{currency(trade.plannedRiskUsd)}</td>

                  <td
                    className={
                      (trade.netPnl ?? 0) >= 0
                        ? "positive"
                        : "negative"
                    }
                  >

                    {currency(trade.netPnl)}
                  </td>

                  <td>{decimal(trade.realizedR)}</td>

                  <td className="actions-cell">
                    {trade.status === "DRAFT" && (
                      <button
                        className="text-button"
                        type="button"
                        onClick={() => editDraft(trade)}
                      >
                        Edit
                      </button>
                    )}

                    {trade.status === "OPEN" && (
                      <button
                        className="text-button close"
                        type="button"
                        onClick={() => beginClose(trade)}
                      >
                        Close
                      </button>

                    )}
                  </td>
                </tr>
              ))}


              {trades.length === 0 && (
                <tr>
                  <td className="empty-state" colSpan={10}>

                    No trades recorded yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}

