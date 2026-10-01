import { Button } from "@codex-local-remote/ui";
import { uiText } from "./locale";

export function PaginationFooter({
  completeLabel,
  error,
  hasMore,
  label,
  loading,
  onLoadMore,
}: {
  completeLabel: string;
  error: string;
  hasMore: boolean;
  label: string;
  loading: boolean;
  onLoadMore: () => void;
}) {
  return (
    <div className="pagination-footer" data-testid="pagination-footer">
      {error ? <p role="alert">{error}</p> : null}
      {hasMore || Boolean(error) ? (
        <Button
          data-testid="pagination-load-more"
          disabled={loading}
          icon={loading ? "activity" : "clock"}
          onClick={onLoadMore}
        >
          {loading
            ? uiText("正在加载…", "Loading…")
            : error
              ? uiText("重试加载", "Retry loading")
              : label}
        </Button>
      ) : (
        <span className="pagination-complete">{completeLabel}</span>
      )}
    </div>
  );
}
