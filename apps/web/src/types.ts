export type TradeStatus = "DRAFT" | "OPEN" | "CLOSED" | "REVIEWED";
export type TradeDirection = "LONG" | "SHORT";

export interface Account {
  id: string;
  name: string;
  externalAccountNumber: string | null;

  propFirm: string | null;
  accountType: string;
  accountSize: number | null;
  active: boolean;
}

export interface Instrument {
  symbol: string;
  name: string;
  exchange: string;
  tickSize: number;
  tickValue: number;
  currency: string;
}

export interface Trade {
  id: string;
  tradeId: string | null;
  status: TradeStatus;
  sessionDate: string;
  tradeNumber: number | null;

  account: {

    id: string;
    name: string;

    propFirm: string | null;
    accountType: string;
  } | null;

  instrument: {
    symbol: string;
    name: string;
    tickSize: number;
    tickValue: number;
  } | null;

  direction: TradeDirection | null;
  contracts: number | null;

  entryTime: string | null;

  exitTime: string | null;

  entryPrice: number | null;
  exitPrice: number | null;

  initialStopPrice: number | null;
  initialStopReference: string | null;
  plannedTargetPrice: number | null;
  plannedTargetReference: string | null;

  setup: string | null;
  primaryLocation: string | null;
  secondaryLocation: string | null;
  trigger: string | null;

  fees: number;
  grossPnl: number | null;
  netPnl: number | null;
  plannedRiskPoints: number | null;
  plannedRiskUsd: number | null;

  realizedR: number | null;

  notes: string | null;

  version: number;
  createdAt: string;
  updatedAt: string;

}

export interface TradeForm {
  sessionDate: string;
  accountId: string;
  instrument: string;
  direction: TradeDirection;
  contracts: string;
  entryTime: string;
  entryPrice: string;
  initialStopPrice: string;
  initialStopReference: string;
  plannedTargetPrice: string;
  plannedTargetReference: string;
  setup: string;

  primaryLocation: string;
  secondaryLocation: string;

  trigger: string;
  notes: string;
}

