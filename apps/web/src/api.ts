import type {
  Account,

  Instrument,
  Trade,
  TradeForm,
} from "./types";


interface ApiErrorBody {
  error?: string;
}

async function request<T>(
  path: string,
  options?: RequestInit,

): Promise<T> {
  const response = await fetch(path, {
    ...options,
    headers: {
      Accept: "application/json",
      ...(options?.body
        ? { "Content-Type": "application/json" }
        : {}),
      ...options?.headers,
    },
  });

  if (!response.ok) {
    let message = `Request failed with status ${response.status}`;

    try {
      const body = (await response.json()) as ApiErrorBody;

      if (body.error) {
        message = body.error;
      }
    } catch {
      // Keep the status-based fallback.
    }


    throw new Error(message);
  }

  return response.json() as Promise<T>;
}

function optionalString(value: string): string | null {
  const normalized = value.trim();
  return normalized === "" ? null : normalized;
}

function optionalNumber(value: string): number | null {
  if (value.trim() === "") {
    return null;
  }

  const number = Number(value);

  if (!Number.isFinite(number)) {
    throw new Error(`"${value}" is not a valid number`);
  }


  return number;
}

function optionalTimestamp(value: string): string | null {
  if (value === "") {
    return null;
  }

  const timestamp = new Date(value);

  if (Number.isNaN(timestamp.getTime())) {
    throw new Error("Entry time is not valid");
  }


  return timestamp.toISOString();
}

function tradePayload(form: TradeForm) {
  return {
    sessionDate: form.sessionDate,
    accountId: optionalString(form.accountId),
    instrument: optionalString(form.instrument),
    direction: optionalString(form.direction),

    contracts: optionalNumber(form.contracts),
    entryTime: optionalTimestamp(form.entryTime),
    entryPrice: optionalNumber(form.entryPrice),
    initialStopPrice: optionalNumber(form.initialStopPrice),
    initialStopReference: optionalString(
      form.initialStopReference,
    ),
    plannedTargetPrice: optionalNumber(
      form.plannedTargetPrice,
    ),
    plannedTargetReference: optionalString(
      form.plannedTargetReference,
    ),
    setup: optionalString(form.setup),
    primaryLocation: optionalString(form.primaryLocation),
    secondaryLocation: optionalString(
      form.secondaryLocation,
    ),
    trigger: optionalString(form.trigger),

    notes: optionalString(form.notes),
  };
}

export const api = {
  listAccounts(): Promise<Account[]> {
    return request<Account[]>("/api/v1/accounts");
  },

  listInstruments(): Promise<Instrument[]> {
    return request<Instrument[]>("/api/v1/instruments");

  },

  listTrades(): Promise<Trade[]> {
    return request<Trade[]>("/api/v1/trades?limit=100");
  },

  createDraft(form: TradeForm): Promise<Trade> {
    return request<Trade>("/api/v1/trades", {
      method: "POST",
      body: JSON.stringify(tradePayload(form)),

    });
  },

  updateDraft(id: string, form: TradeForm): Promise<Trade> {
    return request<Trade>(`/api/v1/trades/${id}`, {
      method: "PUT",
      body: JSON.stringify(tradePayload(form)),
    });
  },

  openTrade(id: string): Promise<Trade> {
    return request<Trade>(`/api/v1/trades/${id}/open`, {
      method: "POST",
    });
  },

  closeTrade(
    id: string,
    exitTime: string,
    exitPrice: string,
    fees: string,
  ): Promise<Trade> {
    const parsedExitPrice = Number(exitPrice);
    const parsedFees = Number(fees);


    if (!Number.isFinite(parsedExitPrice)) {
      throw new Error("Exit price is required");
    }

    if (!Number.isFinite(parsedFees)) {
      throw new Error("Fees must be a valid number");
    }

    return request<Trade>(`/api/v1/trades/${id}/close`, {
      method: "POST",
      body: JSON.stringify({
        exitTime: new Date(exitTime).toISOString(),
        exitPrice: parsedExitPrice,
        fees: parsedFees,
      }),
    });
  },
};

