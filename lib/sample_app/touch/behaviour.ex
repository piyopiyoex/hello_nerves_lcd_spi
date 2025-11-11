defmodule SampleApp.Touch.Behaviour do
  @moduledoc """
  タッチパネル用ドライバの共通インターフェース。
  """

  @callback init(opts :: keyword()) ::
              {:ok, state :: term()} | {:error, term()}

  @callback read_touch(state :: term()) ::
              {:ok, {non_neg_integer(), non_neg_integer()}, state :: term()}
              | {:ok, :no_touch, state :: term()}
              | {:error, term(), state :: term()}
end
