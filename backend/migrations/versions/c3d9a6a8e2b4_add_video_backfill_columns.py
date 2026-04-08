"""add video backfill columns

Revision ID: c3d9a6a8e2b4
Revises: b7f0e6b6c4a1
Create Date: 2026-04-07 00:00:00.000000

"""
from alembic import op


# revision identifiers, used by Alembic.
revision = 'c3d9a6a8e2b4'
down_revision = 'b7f0e6b6c4a1'
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    ADD COLUMN IF NOT EXISTS converted BOOLEAN DEFAULT FALSE,
                    ADD COLUMN IF NOT EXISTS converted_video_url TEXT;

                UPDATE public.videos
                SET converted = COALESCE(converted, FALSE)
                WHERE converted IS NULL;
            END IF;
        END $$;
        """
    )


def downgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    DROP COLUMN IF EXISTS converted_video_url,
                    DROP COLUMN IF EXISTS converted;
            END IF;
        END $$;
        """
    )
